#!/usr/bin/env python3
"""OCI Always Free Block Volume capacity audit. Read-only, no resources created.

Run inside an authenticated Oracle Cloud Shell in the tenancy home region.
Output excludes OCIDs, API keys, tokens and resource names.
"""
import configparser
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

REGION = "eu-marseille-1"
ALWAYS_FREE_GB = 200
TARGET_BOOT_GB = 100


def run_oci(label, *args):
    cmd = ["oci", *args, "--region", REGION, "--output", "json"]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=90)
    except Exception as exc:
        print(f"{label}: FAILED ({type(exc).__name__})")
        return None
    if p.returncode:
        error = (p.stderr or "").lower()
        if "notauthorizedornotfound" in error or "not authorized" in error:
            reason = "not authorized or not found"
        elif "404" in error:
            reason = "HTTP 404 / not supported or permission unavailable"
        else:
            reason = "CLI request failed"
        print(f"{label}: UNAVAILABLE ({reason})")
        return None
    try:
        data = json.loads(p.stdout).get("data")
    except (ValueError, AttributeError):
        print(f"{label}: UNAVAILABLE (invalid response)")
        return None
    print(f"{label}: OK")
    return data


def tenancy_from_config():
    env_id = os.getenv("TENANCY_OCID", "").strip()
    if env_id.startswith("ocid1.tenancy."):
        return env_id
    path = os.getenv("OCI_CLI_CONFIG_FILE") or str(Path.home() / ".oci/config")
    profile = os.getenv("OCI_CLI_PROFILE", "DEFAULT")
    ini = configparser.ConfigParser(interpolation=None)
    try:
        ini.read(path)
        candidate = ini.get(profile, "tenancy")
    except Exception:
        return ""
    return candidate if candidate.startswith("ocid1.tenancy.") else ""


def active_size(items):
    valid = [x for x in items
             if x.get("lifecycle-state") not in ("TERMINATED", "TERMINATING")]
    return len(valid), sum(int(x.get("size-in-gbs") or 0) for x in valid)


def main():
    print("=== OCI Always Free quota audit, READ-ONLY ===")
    print(f"Region to inspect: {REGION}")
    if not shutil.which("oci"):
        sys.exit("Missing Oracle CLI. Run this script from OCI Cloud Shell.")
    tenancy = tenancy_from_config()
    if not tenancy:
        sys.exit("Tenancy OCID unavailable from OCI_CLI_CONFIG_FILE / OCI_CLI_PROFILE. "
                 "Set TENANCY_OCID locally in Cloud Shell and rerun.")
    subscriptions = run_oci("Region subscriptions", "iam", "region-subscription", "list",
                            "--tenancy-id", tenancy)
    if subscriptions is None:
        sys.exit("STOP: Cannot verify that Marseille is the home region.")
    homes = [str(x.get("region-name")) for x in subscriptions if x.get("is-home-region") is True]
    print("Verified home region: " + (", ".join(homes) or "undetermined"))
    if REGION not in homes:
        sys.exit("STOP: Marseille is not the home region. No zero-cost extension recommended.")

    ads = run_oci("Availability domains", "iam", "availability-domain", "list",
                  "--compartment-id", tenancy)
    comps = run_oci("Compartments", "iam", "compartment", "list",
                    "--compartment-id", tenancy, "--compartment-id-in-subtree", "true",
                    "--access-level", "ANY", "--all")
    if not isinstance(ads, list) or not isinstance(comps, list):
        sys.exit("STOP: Cannot inventory accessible volumes; usage is UNKNOWN.")
    compartments = [tenancy] + [c["id"] for c in comps
                                if c.get("lifecycle-state") == "ACTIVE" and c.get("id")]

    # A service limit is not necessarily the same thing as the remaining
    # Always Free allowance. These queries are supplemental evidence.
    availability = None
    for ad in ads:
        ad_name = ad.get("name")
        if not ad_name:
            continue
        r = run_oci("Resource availability (" + str(ad_name).split(":")[-1] + ")",
                    "limits", "resource-availability", "get", "--compartment-id", tenancy,
                    "--service-name", "block-storage", "--limit-name", "total-storage-gb",
                    "--availability-domain", ad_name)
        if isinstance(r, dict):
            print("  Reported available GB:", r.get("available", "unknown"))
            print("  Reported used GB:", r.get("used", "unknown"))
            availability = r

    complete = True
    boot_count = block_count = boot_gb = block_gb = 0
    for comp in compartments:
        for ad in ads:
            ad_name = ad.get("name")
            if not ad_name:
                complete = False
                continue
            # Do not log compartment IDs, boot-volume IDs or resource names.
            boots = run_oci("Boot volume inventory", "bv", "boot-volume", "list",
                            "--compartment-id", comp, "--availability-domain", ad_name,
                            "--all")
            volumes = run_oci("Block volume inventory", "bv", "volume", "list",
                              "--compartment-id", comp, "--availability-domain", ad_name,
                              "--all")
            if not isinstance(boots, list) or not isinstance(volumes, list):
                complete = False
                continue
            bc, bg = active_size(boots)
            vc, vg = active_size(volumes)
            boot_count += bc
            boot_gb += bg
            block_count += vc
            block_gb += vg

    print("=== VISIBLE STORAGE INVENTORY ===")
    print("Accessible compartments examined:", len(compartments))
    print("Boot volumes visible:", boot_count, "| Total GB:", boot_gb)
    print("Block volumes visible:", block_count, "| Total GB:", block_gb)
    print("Visible provisioned total GB:", boot_gb + block_gb)
    print("Always Free reference maximum GB:", ALWAYS_FREE_GB)
    print("Visible quota remainder (NOT billing proof) GB:",
          ALWAYS_FREE_GB - boot_gb - block_gb)
    print("Inventory across accessible compartments complete:", complete)
    print("CAVEAT: IAM may hide other compartments or resources from this user.")
    print("CAVEAT: 200 GB Always Free is tenancy-wide within the home region; "
          "service limits can differ from Free Tier billing eligibility.")
    if not complete:
        print("RESULT: INCONCLUSIVE. No resize permitted.")
    elif boot_gb + block_gb > ALWAYS_FREE_GB:
        print("RESULT: VISIBLE STORAGE EXCEEDS THE ALWAYS FREE ALLOWANCE.")
    elif boot_gb + block_gb + 50 <= ALWAYS_FREE_GB:
        print("RESULT: VISIBLE CAPACITY IS COMPATIBLE with adding 50 GB to an existing "
              "50 GB boot volume, subject to confirming the target volume and OCI "
              "Console Always Free billing designation.")
    else:
        print("RESULT: INSUFFICIENT visible Always Free headroom for +50 GB.")
    print("NO changes have been made to OCI resources.")


if __name__ == "__main__":
    main()
