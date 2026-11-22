#!/usr/bin/env python3
"""
Fix Windows Lab devices in NetBox:
- Update roles for existing devices
- Add IPs to all Windows Lab devices
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

def get_device(name):
    """Get device by name"""
    response = requests.get(
        f"{NETBOX_API}/dcim/devices/",
        headers=headers,
        params={"name": name}
    )
    if response.status_code == 200:
        results = response.json().get("results", [])
        if results:
            return results[0]
    return None

def get_device_role(name):
    """Get device role by name"""
    response = requests.get(
        f"{NETBOX_API}/dcim/device-roles/",
        headers=headers,
        params={"name": name}
    )
    if response.status_code == 200:
        results = response.json().get("results", [])
        if results:
            return results[0]
    return None

def update_device(device_id, data):
    """Update a device"""
    response = requests.patch(
        f"{NETBOX_API}/dcim/devices/{device_id}/",
        headers=headers,
        data=json.dumps(data)
    )
    
    if response.status_code in [200, 201]:
        return response.json()
    else:
        print(f"Error updating device {device_id}: {response.status_code} - {response.text}")
        return None

def create_ip_address(device_id, address):
    """Create an IP address assigned to a device"""
    data = {
        "assigned_object_type": "dcim.device",
        "assigned_object_id": device_id,
        "address": address
    }
    
    response = requests.post(
        f"{NETBOX_API}/ipam/ip-addresses/",
        headers=headers,
        data=json.dumps(data)
    )
    
    if response.status_code in [200, 201]:
        return response.json()
    else:
        print(f"Error creating IP address {address}: {response.status_code} - {response.text}")
        return None

def main():
    print("=" * 60)
    print("Fixing Windows Lab Devices in NetBox")
    print("=" * 60)
    print()
    
    # Get roles
    trusted_host_role = get_device_role("Trusted Host")
    hypervisor_role = get_device_role("Hypervisor")
    
    print("Roles:")
    print(f"  Trusted Host: ID={trusted_host_role['id']}")
    print(f"  Hypervisor: ID={hypervisor_role['id']}")
    print()
    
    # Define updates
    updates = [
        {
            "name": "hp-2",
            "role_id": trusted_host_role["id"],
            "ips": ["192.168.0.122"],
            "description": "Physical Windows notebook. SSHD service running. No hosted VMs. Intel Celeron N3050, 2 cores, 7.86GB RAM"
        },
        {
            "name": "lenovo-thinkcentre",
            "role_id": hypervisor_role["id"],
            "ips": ["192.168.0.170"],
            "description": "Physical Windows host running Hyper-V and Tailscale. Hosts server-252 (K3s control plane node). Tailscale IPv4: 100.120.142.61"
        },
        {
            "name": "hp-1",
            "role_id": hypervisor_role["id"],
            "ips": ["192.168.0.103", "192.168.0.120"],
            "description": "Physical Windows host running Hyper-V. Hosts server-236 (K3s control plane node). Wi-Fi interface at 192.168.0.120 (disconnected)"
        },
        {
            "name": "dell-1",
            "role_id": hypervisor_role["id"],
            "ips": ["192.168.0.123"],
            "description": "Physical Windows host running Hyper-V. Hosts IAMLab (IdentityIQ 8.5 stack in lab.local domain)"
        },
        {
            "name": "fujitsu-esprimo-c720",
            "role_id": None,
            "ips": [],
            "description": "Physical lab client. Intel i3-4150, 4-8GB RAM (unverified). No IP assigned - needs discovery"
        }
    ]
    
    print("Processing Windows Lab devices...")
    print("-" * 60)
    
    for update in updates:
        print(f"\nProcessing {update['name']}...")
        
        device = get_device(update["name"])
        if not device:
            print(f"  ✗ Device not found")
            continue
        
        device_id = device["id"]
        print(f"  Found device ID: {device_id}")
        
        # Update role and description
        update_data = {"description": update["description"]}
        if update["role_id"]:
            update_data["role"] = update["role_id"]
        
        if update_data:
            result = update_device(device_id, update_data)
            if result:
                print(f"  ✓ Device updated")
                if "role" in update_data:
                    print(f"    Role: {result['role']['name']}")
            else:
                print(f"  ✗ Failed to update device")
        
        # Add IPs
        for ip in update["ips"]:
            ip_data = create_ip_address(device_id, f"{ip}/24")
            if ip_data:
                print(f"  ✓ IP {ip} assigned")
            else:
                print(f"  ✗ Failed to assign IP {ip}")
    
    print()
    print("=" * 60)
    print("Windows Lab Devices Updated")
    print("=" * 60)
    
    # Verify all devices
    print("\nVerifying all Windows Lab devices:")
    for update in updates:
        device = get_device(update["name"])
        if device:
            role_name = device.get("role", {}).get("name", "None")
            print(f"  {device['name']}: role={role_name}, description={device.get('description', '')[:50]}...")
        else:
            print(f"  {update['name']}: NOT FOUND")


if __name__ == "__main__":
    main()
