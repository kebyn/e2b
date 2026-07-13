#!/usr/bin/env python3
"""Regression checks for the self-hosted Ansible deployment templates."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
ANSIBLE_DIR = REPO_ROOT / "ansible"
INVENTORY = ANSIBLE_DIR / "inventories/production/hosts.ini"


EXTRA_VARS = {
    "redis_url": "redis-vip.example.com:6379",
    "postgres_password": "test-postgres-password",
    "redis_requirepass": "",
    "admin_token": "test-admin-token",
    "sandbox_access_token_hash_seed": "test-sandbox-access-token-hash-seed",
    "volume_token_signing_key": "ECDSA:test-private-key",
    "nomad_token": "test-nomad-token",
    "local_storage_shared": True,
}


def ansible_bin(name: str) -> str:
    local = REPO_ROOT / ".venv-ansible/bin" / name
    if local.exists():
        return str(local)
    found = shutil.which(name)
    if found:
        return found
    raise unittest.SkipTest(f"{name} not found")


def run_command(args: list[str]) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["ANSIBLE_LOCALHOST_WARNING"] = "false"
    env["ANSIBLE_INVENTORY_UNPARSED_WARNING"] = "false"
    return subprocess.run(
        args,
        cwd=ANSIBLE_DIR,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )


def render_template(
    host: str,
    src: str,
    dest: Path,
    extra_vars: dict[str, object] | None = None,
) -> str:
    variables = EXTRA_VARS | (extra_vars or {})
    result = run_command(
        [
            ansible_bin("ansible"),
            host,
            "-i",
            str(INVENTORY),
            "-c",
            "local",
            "-m",
            "template",
            "-a",
            f"src={src} dest={dest}",
            "-e",
            json.dumps(variables),
        ]
    )
    if result.returncode != 0:
        raise AssertionError(
            f"template render failed for {src}\nSTDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
        )
    return dest.read_text()


class PrivateDeployTemplateTests(unittest.TestCase):
    def test_no_stale_inventory_selector_patterns(self) -> None:
        stale_patterns = [
            "groups['redis_master']",
            'groups["redis_master"]',
            "groups['redis'] | selectattr",
            "groups['postgresql'] | selectattr",
        ]
        offenders: list[str] = []
        for path in ANSIBLE_DIR.rglob("*"):
            if path.suffix not in {".yml", ".j2"}:
                continue
            text = path.read_text()
            for pattern in stale_patterns:
                if pattern in text:
                    offenders.append(f"{path.relative_to(REPO_ROOT)} contains {pattern}")
        self.assertEqual([], offenders)

    def test_all_playbooks_have_valid_syntax(self) -> None:
        for playbook in sorted((ANSIBLE_DIR / "playbooks").glob("*.yml")):
            with self.subTest(playbook=playbook.name):
                result = run_command(
                    [
                        ansible_bin("ansible-playbook"),
                        "-i",
                        str(INVENTORY),
                        str(playbook.relative_to(ANSIBLE_DIR)),
                        "--syntax-check",
                        "-e",
                        json.dumps(EXTRA_VARS),
                    ]
                )
                self.assertEqual(
                    0,
                    result.returncode,
                    f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}",
                )
                self.assertNotIn("apt_repository has been deprecated", result.stderr)

    def test_no_deprecated_apt_repository_tasks(self) -> None:
        offenders: list[str] = []
        for path in ANSIBLE_DIR.rglob("*.yml"):
            text = path.read_text()
            if "apt_repository:" in text or "ansible.builtin.apt_repository:" in text:
                offenders.append(str(path.relative_to(REPO_ROOT)))
        self.assertEqual([], offenders)

    def test_api_env_renders_private_deploy_runtime_vars(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            rendered = render_template(
                "api-1",
                "roles/api/templates/api.env.j2",
                Path(tmp) / "api.env",
            )
        expected_lines = [
            "POSTGRES_CONNECTION_STRING=postgresql://e2b:test-postgres-password@10.0.1.10:5432/e2b?sslmode=disable",
            "REDIS_URL=redis-vip.example.com:6379",
            "REDIS_CLUSTER_URL=",
            "REDIS_TLS_CA_BASE64=",
            "REDIS_POOL_SIZE=160",
            "LOCAL_TEMPLATE_STORAGE_BASE_PATH=/opt/e2b/storage/templates",
            "LOCAL_BUILD_CACHE_STORAGE_BASE_PATH=/opt/e2b/storage/build-cache",
            "AWS_ENDPOINT_URL=",
            "S3_USE_PATH_STYLE=False",
            "DEFAULT_FIRECRACKER_VERSION=v1.14.1_431f1fc",
            "DEFAULT_KERNEL_VERSION=vmlinux-6.1.158",
            "NOMAD_TOKEN=test-nomad-token",
            'ADMIN_TOKEN="test-admin-token"',
            'AUTH_PROVIDER_CONFIG="{\\"jwt\\":[]}"',
            'SANDBOX_ACCESS_TOKEN_HASH_SEED="test-sandbox-access-token-hash-seed"',
            'LAUNCH_DARKLY_API_KEY=""',
            "GCP_PROJECT_ID=",
            "GCP_REGION=us-central1",
        ]
        for line in expected_lines:
            self.assertIn(line, rendered)

    def test_postgres_connection_string_escapes_credentials(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            rendered = render_template(
                "api-1",
                "roles/api/templates/api.env.j2",
                Path(tmp) / "api.env",
                {
                    "postgres_user": "user@example.com",
                    "postgres_password": "p@ss word/with?chars",
                    "postgres_database": "db/name",
                },
            )
        self.assertIn(
            "POSTGRES_CONNECTION_STRING=postgresql://user%40example.com:"
            "p%40ss%20word%2Fwith%3Fchars@10.0.1.10:5432/db%2Fname?sslmode=disable",
            rendered,
        )

    def test_orchestrator_nomad_renders_runtime_vars(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            rendered = render_template(
                "compute-1",
                "roles/orchestrator/templates/orchestrator.nomad.j2",
                Path(tmp) / "orchestrator.nomad",
            )
        expected_lines = [
            'REDIS_URL                   = "redis-vip.example.com:6379"',
            'REDIS_CLUSTER_URL           = ""',
            'REDIS_TLS_CA_BASE64         = ""',
            'REDIS_POOL_SIZE             = "20"',
            'REDIS_MIN_IDLE_CONNS        = "2"',
            'ARTIFACTS_REGISTRY_PROVIDER = "Local"',
            'PROVIDER                    = "gcp"',
            'LOCAL_TEMPLATE_STORAGE_BASE_PATH = "/opt/e2b/storage/templates"',
            'LOCAL_BUILD_CACHE_STORAGE_BASE_PATH = "/opt/e2b/storage/build-cache"',
            'DEFAULT_FIRECRACKER_VERSION = "v1.14.1_431f1fc"',
            'DEFAULT_KERNEL_VERSION      = "vmlinux-6.1.158"',
            'BUSYBOX_VERSION             = "1.36.1"',
            'DOMAIN_NAME                 = "e2b.example.com"',
            'node_pool   = "default"',
            'driver = "raw_exec"',
            'name     = "orchestrator"',
            'name     = "orchestrator-proxy"',
            "memory_max = -1",
        ]
        for line in expected_lines:
            self.assertIn(line, rendered)

    def test_redis_templates_resolve_master_from_inventory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            redis_conf = render_template(
                "redis-2",
                "roles/redis/templates/redis.conf.j2",
                Path(tmp) / "redis.conf",
            )
            sentinel_conf = render_template(
                "sentinel-1",
                "roles/redis/templates/sentinel.conf.j2",
                Path(tmp) / "sentinel.conf",
            )
        self.assertIn("replicaof 10.0.1.20 6379", redis_conf)
        self.assertIn("sentinel monitor mymaster 10.0.1.20 6379", sentinel_conf)
        self.assertIn("bind 127.0.0.1 10.0.1.20", sentinel_conf)
        self.assertIn("bind 127.0.0.1 10.0.1.21", redis_conf)
        self.assertNotIn("requirepass", redis_conf)

    def test_orchestrator_downloads_artifacts_into_runtime_layout(self) -> None:
        tasks = (ANSIBLE_DIR / "roles/orchestrator/tasks/main.yml").read_text()
        expected_snippets = [
            "https://storage.googleapis.com/e2b-prod-public-builds/kernels/{{ default_kernel_version }}/{{ ansible_architecture_normalized }}/vmlinux.bin",
            "test -s /tmp/e2b-{{ default_kernel_version }}-{{ ansible_architecture_normalized }}.part",
            'dest: "{{ e2b_kernels_dir }}/{{ default_kernel_version }}/{{ ansible_architecture_normalized }}/vmlinux.bin"',
            "https://storage.googleapis.com/e2b-prod-public-builds/firecrackers/{{ default_firecracker_version }}/{{ ansible_architecture_normalized }}/firecracker",
            "test -s /tmp/e2b-{{ default_firecracker_version }}-{{ ansible_architecture_normalized }}.part",
            'dest: "{{ e2b_firecracker_dir }}/{{ default_firecracker_version }}/{{ ansible_architecture_normalized }}/firecracker"',
            "https://storage.googleapis.com/e2b-prod-public-builds/busybox/{{ busybox_version }}/{{ ansible_architecture_normalized }}/busybox",
            "remote_src: true",
        ]
        for snippet in expected_snippets:
            self.assertIn(snippet, tasks)
        self.assertNotIn("creates:", tasks)

    def test_nomad_acl_token_is_persisted_and_not_passed_on_command_line(self) -> None:
        deploy = (ANSIBLE_DIR / "playbooks/deploy.yml").read_text()
        nomad_tasks = (ANSIBLE_DIR / "roles/nomad/tasks/main.yml").read_text()
        self.assertIn("nomad_acl_token_file", deploy)
        self.assertIn("nomad_persisted_token", deploy)
        self.assertIn("nomad acl bootstrap -json", nomad_tasks)
        self.assertIn("mode: '0600'", nomad_tasks)
        self.assertIn("NOMAD_TOKEN:", nomad_tasks)
        self.assertIn("no_log: true", nomad_tasks)

        paths = [
            ANSIBLE_DIR / "roles/orchestrator/tasks/main.yml",
            ANSIBLE_DIR / "roles/template-manager/tasks/main.yml",
            ANSIBLE_DIR / "roles/orchestrator/handlers/main.yml",
            ANSIBLE_DIR / "roles/template-manager/handlers/main.yml",
        ]
        for path in paths:
            text = path.read_text()
            self.assertIn("default(nomad_token | default(''))", text, path)
            self.assertIn("NOMAD_TOKEN:", text, path)
            self.assertNotIn("-token=", text, path)
            if path.name == "main.yml" and "handlers" in path.parts:
                self.assertIn("-yes", text, path)
                self.assertIn("run_once: true", text, path)

    def test_nomad_install_and_jobs_support_both_node_pools(self) -> None:
        nomad_tasks = (ANSIBLE_DIR / "roles/nomad/tasks/main.yml").read_text()
        client_config = (ANSIBLE_DIR / "roles/nomad/templates/client.hcl.j2").read_text()
        self.assertIn("linux_{{ ansible_architecture_normalized }}.zip", nomad_tasks)
        self.assertNotIn("linux_amd64.zip", nomad_tasks)
        self.assertIn("nomad_installed_version", nomad_tasks)
        self.assertIn("nomad_install_required", nomad_tasks)
        self.assertIn("nomad_{{ nomad_version }}_SHA256SUMS", nomad_tasks)
        self.assertIn('node_pool = "{{ nomad_node_pool }}"', client_config)
        self.assertIn('plugin "raw_exec"', client_config)
        self.assertIn("enabled = true", client_config)

        with tempfile.TemporaryDirectory() as tmp:
            rendered = render_template(
                "build-1",
                "roles/template-manager/templates/template-manager.nomad.j2",
                Path(tmp) / "template-manager.nomad",
            )
        self.assertIn('node_pool   = "build"', rendered)
        self.assertIn('driver = "raw_exec"', rendered)
        self.assertIn('name     = "template-manager"', rendered)
        self.assertIn("memory_max = -1", rendered)
        self.assertIn(
            'LOCAL_UPLOAD_BASE_URL        = "http://${attr.unique.network.ip-address}:5008"',
            rendered,
        )

        template_manager_tasks = (
            ANSIBLE_DIR / "roles/template-manager/tasks/main.yml"
        ).read_text()
        self.assertIn("include_role:", template_manager_tasks)
        self.assertIn("name: orchestrator", template_manager_tasks)
        self.assertIn("name: docker.io", template_manager_tasks)

    def test_orchestrator_configures_nbd_capacity_before_loading_module(self) -> None:
        tasks = (ANSIBLE_DIR / "roles/orchestrator/tasks/main.yml").read_text()
        options_pos = tasks.index("options nbd nbds_max={{ nbd_max_devices }}")
        load_pos = tasks.index("name: 加载 NBD 内核模块")
        self.assertLess(options_pos, load_pos)
        self.assertIn('content: "nbd\\ntun\\n"', tasks)
        self.assertIn("/sys/module/nbd/parameters/nbds_max", tasks)
        self.assertIn("path: /dev/kvm", tasks)
        self.assertNotIn("nbd nbds_max=256", tasks)

    def test_postgres_replica_initialization_is_idempotent(self) -> None:
        tasks = (ANSIBLE_DIR / "roles/postgresql/tasks/main.yml").read_text()
        self.assertIn("standby.signal", tasks)
        self.assertIn("postgres_replica_rebuild", tasks)
        self.assertGreaterEqual(tasks.count("postgres_replica_needs_init | bool"), 4)
        self.assertIn("meta: flush_handlers", tasks)
        self.assertIn("apt.postgresql.org/pub/repos/apt", tasks)
        self.assertIn("goose_linux_{{ goose_architecture_normalized }}", tasks)
        self.assertIn("infra/packages/db/migrations/", tasks)
        self.assertIn("GOOSE_DBSTRING:", tasks)

    def test_nginx_routes_internal_grpc_and_optional_dashboard(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            nginx = render_template(
                "lb-1",
                "roles/nginx/templates/e2b.conf.j2",
                Path(tmp) / "e2b.conf",
                {"dashboard_enabled": True},
            )
        self.assertIn("listen 5009 http2;", nginx)
        self.assertIn("grpc_pass grpc://e2b_api_grpc;", nginx)
        self.assertIn("server_name dashboard.e2b.example.com;", nginx)
        self.assertIn("server_name dashboard-api.e2b.example.com;", nginx)

    def test_dashboard_uses_bun_and_current_ory_environment_contract(self) -> None:
        dashboard_vars = {
            "dashboard_session_secret": "test-dashboard-session-secret-32chars",
            "ory_sdk_url": "https://ory.example.com",
            "ory_project_api_token": "test-ory-token",
            "ory_issuer_url": "https://auth.example.com",
            "dashboard_ory_oauth2_client_id": "dashboard-client",
            "dashboard_ory_oauth2_client_secret": "dashboard-secret",
            "dashboard_ory_oauth2_cli_client_id": "cli-client",
            "dashboard_ory_oauth2_audience": "https://api.e2b.example.com",
        }
        with tempfile.TemporaryDirectory() as tmp:
            env_file = render_template(
                "dashboard-1",
                "roles/dashboard/templates/dashboard.env.j2",
                Path(tmp) / ".env.production",
                dashboard_vars,
            )
            service = render_template(
                "dashboard-1",
                "roles/dashboard/templates/e2b-dashboard.service.j2",
                Path(tmp) / "e2b-dashboard.service",
                dashboard_vars,
            )

        for expected in [
            'DASHBOARD_API_ADMIN_TOKEN="test-admin-token"',
            'E2B_SESSION_SECRET="test-dashboard-session-secret-32chars"',
            'ORY_OAUTH2_CLIENT_ID="dashboard-client"',
            'ORY_OAUTH2_CLI_CLIENT_ID="cli-client"',
            'ORY_OAUTH2_AUDIENCE="https://api.e2b.example.com"',
            'NEXT_PUBLIC_E2B_DOMAIN="e2b.example.com"',
            'NEXT_PUBLIC_INFRA_API_URL="http://api.e2b.example.com"',
            'NEXT_PUBLIC_DASHBOARD_API_URL="http://dashboard-api.e2b.example.com"',
            'NEXT_PUBLIC_E2B_SANDBOX_URL="http://sandbox.e2b.example.com"',
        ]:
            self.assertIn(expected, env_file)

        dashboard_tasks = (ANSIBLE_DIR / "roles/dashboard/tasks/main.yml").read_text()
        self.assertIn("bun-v{{ dashboard_bun_version }}", dashboard_tasks)
        self.assertIn("SHASUMS256.txt", dashboard_tasks)
        self.assertIn("dashboard_bun_install_required", dashboard_tasks)
        self.assertIn('version: "{{ dashboard_version }}"', dashboard_tasks)
        self.assertIn("dashboard_build_min_memory_mb", dashboard_tasks)
        self.assertIn("/usr/local/bin/bun install --frozen-lockfile", dashboard_tasks)
        self.assertIn("/usr/local/bin/bun run build", dashboard_tasks)
        self.assertNotIn("npm:", dashboard_tasks)
        self.assertIn("ExecStart=/usr/local/bin/bun run start", service)

    def test_systemd_cpu_quotas_use_percentages(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            api_unit = render_template(
                "api-1",
                "roles/api/templates/e2b-api.service.j2",
                Path(tmp) / "e2b-api.service",
            )
            proxy_unit = render_template(
                "proxy-1",
                "roles/client-proxy/templates/e2b-client-proxy.service.j2",
                Path(tmp) / "e2b-client-proxy.service",
            )
        self.assertIn("CPUQuota=200%", api_unit)
        self.assertIn("CPUQuota=100%", proxy_unit)


if __name__ == "__main__":
    unittest.main()
