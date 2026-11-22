#!/usr/bin/env python3
"""
Simplified script to add Windows Lab devices to NetBox.
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

def get_manufacturer(name):
    """Get manufacturer by name"""
    response = requests.get(
        f"{NETBOX_API}/dcim/manufacturers/",
        headers=headers,
        params={"name": name}
    )
    if response.status_code == 200:
        results = response.json().get("results", [])
        if results:
            return results[0]
    return None

def get_device_type(manufacturer_name, model):
    """Get device type by manufacturer and model"""
    manufacturer = get_manufacturer(manufacturer_name)
    if not manufacturer:
        return None
    
    response = requests.get(
        f"{NETBOX_API}/dcim/device-types/",
        headers=headers,
        params={"manufacturer_id": manufacturer["id"], "model": model}
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

def create_device(name, device_type_id, device_role_id, site_id, description="", status="active"):
    """Create a device"""
    data = {
        "name": name,
        "device_type": device_type_id,
        "device_role": device_role_id,
        "site": site_id,
        "status": status,
        "description": description
    }
    
    response = requests.post(
        f"{NETBOX_API}/dcim/devices/",
        headers=headers,
        data=json.dumps(data)
    )
    
    if response.status_code in [200, 201]:
        return response.json()
    else:
        print(f"Error creating device {name}: {response.status_code} - {response.text}")
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
    
    # Get device roles
    print("Getting device roles...")
    hypervisor_role = get_device_role("Hypervisor")
    trusted_host_role = get_device_role("Trusted Host")
    client_role = get_device_role("Client")
    print(f"  Hypervisor: {hypervisor_role['name'] if hypervisor_role else 'NOT FOUND'}")
    print(f"  Trusted Host: {trusted_host_role['name'] if trusted_host_role else 'NOT FOUND'}")
    print(f"  Client: {client_role['name'] if client_role else 'NOT FOUND'}")
    print()
    
    # Define devices
    devices = [
        {
            "name": "hp-1",
            "manufacturer": "HP",
            "model": "Desktop",
            "role": "Hypervisor",
            "ip": "192.168.0.103",
            "additional_ips": ["192.168.0.120"],
            "description": "Physical Windows host running Hyper-V. Hosts server-236 (K3s control plane node). Wi-Fi interface at 192.168.0.120 (disconnected)"
        },
        {
            "name": "hp-2",
            "manufacturer": "HP",
            "model": "Notebook",
            "role": "Trusted Host",
            "ip": "192.168.0.122",
            "additional_ips": [],
            "description": "Physical Windows notebook. SSHD service running. No hosted VMs. Intel Celeron N3050, 2 cores, 7.86GB RAM"
        },
        {
            "name": "dell-1",
            "manufacturer": "Dell",
            "model": "Desktop",
            "role": "Hypervisor",
            "ip": "192.168.0.123",
            "additional_ips": [],
            "description": "Physical Windows host running Hyper-V. Hosts IAMLab (IdentityIQ 8.5 stack in lab.local domain)"
        },
        {
            "name": "lenovo-thinkcentre",
            "manufacturer": "Lenovo",
            "model": "ThinkCentre",
            "role": "Hypervisor",
            "ip": "192.168.0.170",
            "additional_ips": [],
            "description": "Physical Windows host running Hyper-V and Tailscale. Hosts server-252 (K3s control plane node). Tailscale IPv4: 100.120.142.61"
        },
        {
            "name": "fujitsu-esprimo-c720",
            "manufacturer": "Fujitsu",
            "model": "ESPRIMO C720",
            "role": "Client",
            "ip": None,
            "additional_ips": [],
            "description": "Physical lab client. Intel i3-4150, 4-8GB RAM (unverified). No IP assigned - needs discovery"
        }
    ]
    
    # Create devices
    print("Creating Windows Lab devices...")
    print("-" * 60)
    
    created_devices = []
    for device in devices:
        print(f"Creating {device['name']}...")
        
        # Get device type
        device_type = get_device_type(device["manufacturer"], device["model"])
        if not device_type:
            print(f"  ✗ Device type not found for {device['manufacturer']} {device['model']}")
            continue
        
        # Get device role
        role_map = {
            "Hypervisor": hypervisor_role,
            "Trusted Host": trusted_host_role,
            "Client": client_role
        }
        device_role = role_map.get(device["role"])
        if not device_role:
            print(f"  ✗ Device role not found: {device['role']}")
            continue
        
        # Create device
        device_data = create_device(
            name=device["name"],
            device_type_id=device_type["id"],
            device_role_id=device_role["id"],
            site_id=site_id,
            description=device["description"],
            status="active"
        )
        
        if device_data:
            device_id = device_data["id"]
            created_devices.append({"name": device["name"], "id": device_id})
            print(f"  ✓ Device created (ID: {device_id})")
            
            # Create primary IP if exists
            if device["ip"]:
                ip_data = create_ip_address(
                    device_id=device_id,
                    address=f"{device['ip']}/24"
                )
                if ip_data:
                    print(f"  ✓ Primary IP {device['ip']} assigned")
            
            # Create additional IPs
            for additional_ip in device["additional_ips"]:
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
    
    if len(created_devices) == len(devices):
        print("\n✓ All Windows Lab devices successfully added to NetBox!")
    else:
        print(f"\n⚠ {len(devices) - len(created_devices)} devices failed to create")


if __name__ == "__main__":
    main()
