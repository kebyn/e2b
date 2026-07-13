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
    "redis_requirepass": "test-redis-password",
    "admin_token": "test-admin-token",
    "volume_token_signing_key": "ECDSA:test-private-key",
    "nomad_token": "test-nomad-token",
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


def render_template(host: str, src: str, dest: Path) -> str:
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
            json.dumps(EXTRA_VARS),
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

    def test_deploy_playbook_syntax(self) -> None:
        result = run_command(
            [
                ansible_bin("ansible-playbook"),
                "-i",
                str(INVENTORY),
                "playbooks/deploy.yml",
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
        ]
        for line in expected_lines:
            self.assertIn(line, rendered)

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
            'LOCAL_TEMPLATE_STORAGE_BASE_PATH = "/opt/e2b/storage/templates"',
            'LOCAL_BUILD_CACHE_STORAGE_BASE_PATH = "/opt/e2b/storage/build-cache"',
            'DEFAULT_FIRECRACKER_VERSION = "v1.14.1_431f1fc"',
            'DEFAULT_KERNEL_VERSION      = "vmlinux-6.1.158"',
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

    def test_orchestrator_downloads_artifacts_into_runtime_layout(self) -> None:
        tasks = (ANSIBLE_DIR / "roles/orchestrator/tasks/main.yml").read_text()
        expected_snippets = [
            "mkdir -p {{ e2b_kernels_dir }}/{{ default_kernel_version }}/{{ ansible_architecture_normalized }}",
            "https://storage.googleapis.com/e2b-prod-public-builds/kernels/{{ default_kernel_version }}/{{ ansible_architecture_normalized }}/vmlinux.bin",
            "-O {{ e2b_kernels_dir }}/{{ default_kernel_version }}/{{ ansible_architecture_normalized }}/vmlinux.bin",
            "creates: \"{{ e2b_kernels_dir }}/{{ default_kernel_version }}/{{ ansible_architecture_normalized }}/vmlinux.bin\"",
            "mkdir -p {{ e2b_firecracker_dir }}/{{ default_firecracker_version }}/{{ ansible_architecture_normalized }}",
            "https://storage.googleapis.com/e2b-prod-public-builds/firecrackers/{{ default_firecracker_version }}/{{ ansible_architecture_normalized }}/firecracker",
            "-O {{ e2b_firecracker_dir }}/{{ default_firecracker_version }}/{{ ansible_architecture_normalized }}/firecracker",
            "creates: \"{{ e2b_firecracker_dir }}/{{ default_firecracker_version }}/{{ ansible_architecture_normalized }}/firecracker\"",
        ]
        for snippet in expected_snippets:
            self.assertIn(snippet, tasks)

    def test_nomad_job_commands_fallback_to_configured_token(self) -> None:
        paths = [
            ANSIBLE_DIR / "roles/orchestrator/tasks/main.yml",
            ANSIBLE_DIR / "roles/template-manager/tasks/main.yml",
            ANSIBLE_DIR / "roles/orchestrator/handlers/main.yml",
            ANSIBLE_DIR / "roles/template-manager/handlers/main.yml",
        ]
        for path in paths:
            text = path.read_text()
            self.assertIn("default(nomad_token | default(''))", text, path)
            self.assertNotIn("| default(''))) if (nomad_acl_enabled | bool)", text, path)
            self.assertNotIn("shell: nomad job restart", text, path)


if __name__ == "__main__":
    unittest.main()
