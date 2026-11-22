#!/usr/bin/env python3
"""
Add Windows Lab devices to NetBox using the API.
This script creates physical Windows hosts that manage the homelab infrastructure.
"""

import requests
import json

NETBOX_API = "http://netbox.tail35421d.ts.net/api"
TOKEN = "nbt_3wuFtgqFBAE6.oszkkdvkJuUDy68III11y0YBaDftq6jBSsiJ8vpS"

headers = {
    "Authorization": f"Bearer {TOKEN}",
    "Accept": "application/json",
    "Content-Type": "application/json"
}

# Cache for storing created/getted objects
manufacturers_cache = {}
device_types_cache = {}
device_roles_cache = {}
statuses_cache = {}

def get_or_create_manufacturer(name, slug=None):
    """Get or create a manufacturer"""
    if not slug:
        slug = name.lower().replace(" ", "-")
    
    # Check cache
    if slug in manufacturers_cache:
        return manufacturers_cache[slug]
    
    # Try to get existing
    response = requests.get(
        f"{NETBOX_API}/dcim/manufacturers/",
        headers=headers,
        params={"slug": slug}
    )
    
    if response.status_code == 200:
        results = response.json().get("results", [])
        if results:
            manufacturers_cache[slug] = results[0]["id"]
            return results[0]["id"]
    
    # Create new
    data = {"name": name, "slug": slug}
    response = requests.post(
        f"{NETBOX_API}/dcim/manufacturers/",
        headers=headers,
        data=json.dumps(data)
    )
    
    if response.status_code == 201:
        manufacturer_id = response.json()["id"]
        manufacturers_cache[slug] = manufacturer_id
        return manufacturer_id
    else:
        print(f"Error creating manufacturer {name}: {response.text}")
        return None


def get_or_create_device_type(manufacturer_id, model, slug=None):
    """Get or create a device type"""
    if not slug:
        slug = model.lower().replace(" ", "-").replace("/", "-")
    
    cache_key = f"{manufacturer_id}-{slug}"
    if cache_key in device_types_cache:
        return device_types_cache[cache_key]
    
    # Try to get existing by manufacturer and model
    response = requests.get(
        f"{NETBOX_API}/dcim/device-types/",
        headers=headers,
        params={"manufacturer_id": manufacturer_id, "model": model}
    )
    
    if response.status_code == 200:
        results = response.json().get("results", [])
        if results:
            device_types_cache[cache_key] = results[0]["id"]
            return results[0]["id"]
    
    # Try by slug
    response = requests.get(
        f"{NETBOX_API}/dcim/device-types/",
        headers=headers,
        params={"slug": slug}
    )
    
    if response.status_code == 200:
        results = response.json().get("results", [])
        if results:
            device_types_cache[cache_key] = results[0]["id"]
            return results[0]["id"]
    
    # Create new
    data = {
        "manufacturer": manufacturer_id,
        "model": model,
        "slug": slug
    }
    response = requests.post(
        f"{NETBOX_API}/dcim/device-types/",
        headers=headers,
        data=json.dumps(data)
    )
    
    if response.status_code == 201:
        device_type_id = response.json()["id"]
        device_types_cache[cache_key] = device_type_id
        return device_type_id
    else:
        print(f"Error creating device type {model}: {response.text}")
        return None


def get_or_create_device_role(name, color="000000", slug=None):
    """Get or create a device role"""
    if not slug:
        slug = name.lower().replace(" ", "-")
    
    # Check cache
    if slug in device_roles_cache:
        return device_roles_cache[slug]
    
    # Try to get existing
    response = requests.get(
        f"{NETBOX_API}/dcim/device-roles/",
        headers=headers,
        params={"slug": slug}
    )
    
    if response.status_code == 200:
        results = response.json().get("results", [])
        if results:
            device_roles_cache[slug] = results[0]["id"]
            return results[0]["id"]
    
    # Create new
    data = {
        "name": name,
        "slug": slug,
        "color": color
    }
    response = requests.post(
        f"{NETBOX_API}/dcim/device-roles/",
        headers=headers,
        data=json.dumps(data)
    )
    
    if response.status_code == 201:
        role_id = response.json()["id"]
        device_roles_cache[slug] = role_id
        return role_id
    else:
        print(f"Error creating device role {name}: {response.text}")
        return None


def get_or_create_status(name):
    """Get or create a device status"""
    # Check cache
    if name in statuses_cache:
        return statuses_cache[name]
    
    # Try to get existing - use the exact endpoint
    response = requests.get(
        f"{NETBOX_API}/dcim/device-statuses/",
        headers=headers
    )
    
    if response.status_code == 200:
        results = response.json().get("results", [])
        for result in results:
            if result["name"] == name:
                statuses_cache[name] = result["id"]
                return result["id"]
    
    # Create new
    data = {"name": name, "slug": name.lower().replace(" ", "-")}
    response = requests.post(
        f"{NETBOX_API}/dcim/device-statuses/",
        headers=headers,
        data=json.dumps(data)
    )
    
    if response.status_code == 201:
        status_id = response.json()["id"]
        statuses_cache[name] = status_id
        return status_id
    else:
        print(f"Error creating status {name}: {response.text}")
        return None


def create_device(name, device_type_id, device_role_id, site_id, status_id, description=""):
    """Create a device"""
    data = {
        "name": name,
        "device_type": device_type_id,
        "device_role": device_role_id,
        "site": site_id,
        "status": status_id,
        "description": description
    }
    
    response = requests.post(
        f"{NETBOX_API}/dcim/devices/",
        headers=headers,
        data=json.dumps(data)
    )
    
    if response.status_code == 201:
        return response.json()
    else:
        print(f"Error creating device {name}: {response.text}")
        return None


def create_ip_address(device_id, address, prefix_id=None):
    """Create an IP address assigned to a device"""
    data = {
        "assigned_object_type": "dcim.device",
        "assigned_object_id": device_id,
        "address": address
    }
    
    if prefix_id:
        data["prefix"] = prefix_id
    
    response = requests.post(
        f"{NETBOX_API}/ipam/ip-addresses/",
        headers=headers,
        data=json.dumps(data)
    )
    
    if response.status_code == 201:
        return response.json()
    else:
        print(f"Error creating IP address {address}: {response.text}")
        return None


def get_site(site_name):
    """Get site by name"""
    response = requests.get(
        f"{NETBOX_API}/dcim/sites/",
        headers=headers,
        params={"name": site_name}
    )
    
    if response.status_code == 200:
        results = response.json().get("results", [])
        if results:
            return results[0]
    return None


def get_prefix(prefix):
    """Get prefix by prefix"""
    response = requests.get(
        f"{NETBOX_API}/ipam/prefixes/",
        headers=headers,
        params={"prefix": prefix}
    )
    
    if response.status_code == 200:
        results = response.json().get("results", [])
        if results:
            return results[0]
    return None


def main():
    print("=" * 60)
    print("Adding Windows Lab Devices to NetBox")
    print("=" * 60)
    print()
    
    # Get site
    site = get_site("K3s Homelab")
    if not site:
        print("ERROR: Site 'K3s Homelab' not found!")
        return
    site_id = site["id"]
    print(f"✓ Site: {site['name']} (ID: {site_id})")
    print()
    
    # Get prefix
    prefix = get_prefix("192.168.0.0/24")
    prefix_id = prefix["id"] if prefix else None
    print(f"✓ Prefix: {prefix['prefix']} (ID: {prefix_id})")
    print()
    
    # Get or create manufacturers
    print("Setting up manufacturers...")
    hp_id = get_or_create_manufacturer("HP")
    dell_id = get_or_create_manufacturer("Dell")
    lenovo_id = get_or_create_manufacturer("Lenovo")
    fujitsu_id = get_or_create_manufacturer("Fujitsu")
    print(f"  HP: {hp_id}, Dell: {dell_id}, Lenovo: {lenovo_id}, Fujitsu: {fujitsu_id}")
    print()
    
    # Get or create device types
    print("Setting up device types...")
    hp_notebook_type = get_or_create_device_type(hp_id, "Notebook", "hp-notebook")
    hp_desktop_type = get_or_create_device_type(hp_id, "Desktop", "hp-desktop")
    dell_desktop_type = get_or_create_device_type(dell_id, "Desktop", "dell-desktop")
    lenovo_thinkcentre_type = get_or_create_device_type(lenovo_id, "ThinkCentre", "lenovo-thinkcentre")
    fujitsu_esprimo_type = get_or_create_device_type(fujitsu_id, "ESPRIMO C720", "fujitsu-esprimo-c720")
    print(f"  HP Notebook: {hp_notebook_type}, HP Desktop: {hp_desktop_type}")
    print(f"  Dell Desktop: {dell_desktop_type}, Lenovo ThinkCentre: {lenovo_thinkcentre_type}")
    print(f"  Fujitsu ESPRIMO: {fujitsu_esprimo_type}")
    print()
    
    # Get or create device roles
    print("Setting up device roles...")
    hypervisor_role = get_or_create_device_role("Hypervisor", "ff00ff")
    trusted_host_role = get_or_create_device_role("Trusted Host", "00ffaa")
    client_role = get_or_create_device_role("Client", "aaff00")
    print(f"  Hypervisor: {hypervisor_role}, Trusted Host: {trusted_host_role}, Client: {client_role}")
    print()
    
    # Get or create statuses
    print("Setting up statuses...")
    active_status = get_or_create_status("Active")
    offline_status = get_or_create_status("Offline")
    print(f"  Active: {active_status}, Offline: {offline_status}")
    print()
    
    # Define Windows Lab devices
    windowslab_devices = [
        {
            "name": "hp-1",
            "device_type_id": hp_desktop_type,
            "device_role_id": hypervisor_role,
            "status_id": active_status,
            "ip": "192.168.0.103",
            "description": "Physical Windows host running Hyper-V. Hosts server-236 (K3s control plane node). Wi-Fi interface at 192.168.0.120 (disconnected)",
            "additional_ips": ["192.168.0.120"]
        },
        {
            "name": "hp-2",
            "device_type_id": hp_notebook_type,
            "device_role_id": trusted_host_role,
            "status_id": active_status,
            "ip": "192.168.0.122",
            "description": "Physical Windows notebook. SSHD service running. No hosted VMs. Intel Celeron N3050, 2 cores, 7.86GB RAM",
            "additional_ips": []
        },
        {
            "name": "dell-1",
            "device_type_id": dell_desktop_type,
            "device_role_id": hypervisor_role,
            "status_id": active_status,
            "ip": "192.168.0.123",
            "description": "Physical Windows host running Hyper-V. Hosts IAMLab (IdentityIQ 8.5 stack in lab.local domain)",
            "additional_ips": []
        },
        {
            "name": "lenovo-thinkcentre",
            "device_type_id": lenovo_thinkcentre_type,
            "device_role_id": hypervisor_role,
            "status_id": active_status,
            "ip": "192.168.0.170",
            "description": "Physical Windows host running Hyper-V and Tailscale. Hosts server-252 (K3s control plane node). Tailscale IPv4: 100.120.142.61",
            "additional_ips": []
        },
        {
            "name": "fujitsu-esprimo-c720",
            "device_type_id": fujitsu_esprimo_type,
            "device_role_id": client_role,
            "status_id": offline_status,
            "ip": None,
            "description": "Physical lab client. Intel i3-4150, 4-8GB RAM (unverified). No IP assigned - needs discovery",
            "additional_ips": []
        }
    ]
    
    # Create devices
    print("Creating Windows Lab devices...")
    print("-" * 60)
    
    created_devices = []
    for device_config in windowslab_devices:
        print(f"Creating {device_config['name']}...")
        
        device_data = create_device(
            name=device_config["name"],
            device_type_id=device_config["device_type_id"],
            device_role_id=device_config["device_role_id"],
            site_id=site_id,
            status_id=device_config["status_id"],
            description=device_config["description"]
        )
        
        if device_data:
            device_id = device_data["id"]
            created_devices.append({"name": device_config["name"], "id": device_id})
            print(f"  ✓ Device created (ID: {device_id})")
            
            # Create primary IP if exists
            if device_config["ip"]:
                ip_data = create_ip_address(
                    device_id=device_id,
                    address=f"{device_config['ip']}/24"
                )
                if ip_data:
                    print(f"  ✓ Primary IP {device_config['ip']} assigned")
            
            # Create additional IPs
            for additional_ip in device_config["additional_ips"]:
                ip_data = create_ip_address(
                    device_id=device_id,
                    address=f"{additional_ip}/24"
                )
                if ip_data:
                    print(f"  ✓ Additional IP {additional_ip} assigned")
        else:
            print(f"  ✗ Failed to create device")
        
        print()
    
    # Summary
    print("=" * 60)
    print("Windows Lab Devices Added to NetBox")
    print("=" * 60)
    print(f"\nTotal devices created: {len(created_devices)}")
    for device in created_devices:
        print(f"  - {device['name']} (ID: {device['id']})")
    
    print("\n✓ Windows Lab documentation in NetBox is complete!")


if __name__ == "__main__":
    main()
