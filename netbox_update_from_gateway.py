#!/usr/bin/env python3
"""
Update NetBox with data from Vodafone Station gateway scan.
This script:
1. Creates missing devices
2. Updates existing devices with MAC addresses
3. Adds custom fields for better tracking
"""

import requests
import json
import re

NETBOX_API = "http://netbox.tail35421d.ts.net/api"
TOKEN = "nbt_3wuFtgqFBAE6.oszkkdvkJuUDy68III11y0YBaDftq6jBSsiJ8vpS"

headers = {
    "Authorization": f"Bearer {TOKEN}",
    "Accept": "application/json",
    "Content-Type": "application/json"
}

# Gateway data from Vodafone Station
ACTIVE_DEVICES = [
    {"host": "MacBook-Pro-von-medneo", "ip": "192.168.0.9", "mac": "8c:85:90:54:89:52", "type": "Static", "category": "Laptop"},
    {"host": "kubernetes1", "ip": "192.168.0.19", "mac": "90:1b:0e:89:b9:66", "type": "Static", "category": "K3s"},
    {"host": "kubernetes2", "ip": "192.168.0.20", "mac": "40:b0:76:0f:3c:72", "type": "Static", "category": "K3s"},
    {"host": "NUC", "ip": "192.168.0.21", "mac": "c0:3f:d5:6d:45:85", "type": "Static", "category": "K3s"},
    {"host": "kubernetes3", "ip": "192.168.0.22", "mac": "40:8d:5c:aa:d9:1f", "type": "Static", "category": "K3s"},
    {"host": "kubernetes4", "ip": "192.168.0.23", "mac": "64:00:6a:62:72:dc", "type": "Static", "category": "K3s"},
    {"host": "kubernetes5", "ip": "192.168.0.24", "mac": "44:8a:5b:2c:b8:83", "type": "Static", "category": "K3s"},
    {"host": "kubernetes6", "ip": "192.168.0.25", "mac": "90:1b:0e:56:d7:bb", "type": "Static", "category": "K3s"},
    {"host": "DESKTOP-F3QNNA5", "ip": "192.168.0.170", "mac": "00:23:24:bd:64:3f", "type": "DHCP", "category": "Hypervisor"},
    {"host": "HP-2", "ip": "192.168.0.122", "mac": "fc:3f:db:86:1a:81", "type": "Static", "category": "Hypervisor"},
    {"host": "NASECDE55", "ip": "192.168.0.128", "mac": "00:08:9b:ec:de:55", "type": "Static", "category": "NAS"},
    {"host": "install-Virtual-Machine", "ip": "192.168.0.236", "mac": "00:15:5d:00:78:2e", "type": "DHCP", "category": "VM"},
    {"host": "install-Virtual-Machine-1", "ip": "192.168.0.237", "mac": "00:15:5d:00:78:2f", "type": "DHCP", "category": "VM"},
    {"host": "Suryendu-s-Gadget", "ip": "192.168.0.234", "mac": "92:68:25:07:c6:07", "type": "DHCP", "category": "Mobile"},
    {"host": "iPhone", "ip": "192.168.0.213", "mac": "56:75:93:ca:bc:f9", "type": "DHCP", "category": "Mobile"},
    {"host": "M2004J19C-Redmi9Prim", "ip": "192.168.0.97", "mac": "dc:b7:2e:33:7c:18", "type": "DHCP", "category": "Mobile"},
    {"host": "dehepcn6iYf", "ip": "192.168.0.189", "mac": "e0:3a:aa:64:a2:76", "type": "DHCP", "category": "Unknown"},
    {"host": "Unknown", "ip": "192.168.0.222", "mac": "94:be:46:56:85:4b", "type": "DHCP", "category": "Unknown"},
]

INACTIVE_DEVICES = [
    {"host": "DELL-1", "ip": "192.168.0.123", "mac": "5c:f9:dd:6b:7b:cf", "type": "Static", "category": "Hypervisor"},
    {"host": "DESKTOP-32DRFM7", "ip": "192.168.0.120", "mac": "f0:d5:bf:26:11:be", "type": "Static", "category": "Hypervisor"},
    {"host": "DESKTOP-8D64UC6", "ip": "192.168.0.75", "mac": "90:1b:0e:3c:59:08", "type": "Static", "category": "Unknown"},
    {"host": "DESKTOP-EAJUV53", "ip": "192.168.0.18", "mac": "44:1c:a8:45:5a:97", "type": "DHCP", "category": "Unknown"},
    {"host": "kubernetes7", "ip": "192.168.0.26", "mac": "6c:c2:17:e9:a4:e5", "type": "Static", "category": "K3s"},
    {"host": "kubernetes8-debian", "ip": "192.168.0.27", "mac": "00:14:0b:45:02:83", "type": "Static", "category": "K3s"},
    {"host": "suryendub-VMware-Virtual-Platform", "ip": "192.168.0.189", "mac": "00:0c:29:8d:1f:41", "type": "DHCP", "category": "VM"},
    {"host": "Unknown", "ip": "192.168.0.99", "mac": "c8:9e:43:a8:ad:f6", "type": "DHCP", "category": "Unknown"},
    {"host": "Unknown", "ip": "192.168.0.103", "mac": "c8:d3:ff:6a:72:2e", "type": "Static", "category": "Unknown"},
    {"host": "Unknown", "ip": "192.168.0.116", "mac": "28:f3:66:b5:e1:ee", "type": "DHCP", "category": "Unknown"},
    {"host": "Unknown", "ip": "192.168.0.252", "mac": "00:15:5d:00:aa:03", "type": "Static", "category": "K3s"},
]

# NetBox device name mappings
NETBOX_NAME_MAPPINGS = {
    "DESKTOP-F3QNNA5": "lenovo-thinkcentre",
    "HP-2": "hp-2",
    "NASECDE55": "nas",
    "install-Virtual-Machine": "server-236",
    "install-Virtual-Machine-1": "server-237",
    "NUC": "nuc",
    "DELL-1": "dell-1",
    "kubernetes7": "kubernetes7",
    "kubernetes8-debian": "kubernetes8-debian",
    "Unknown": "unknown",
}

def get_site(site_name="K3s Homelab"):
    response = requests.get(
        f"{NETBOX_API}/dcim/sites/",
        headers=headers,
        params={"name": site_name}
    )
    if response.status_code == 200:
        results = response.json().get("results", [])
        return results[0] if results else None
    return None

def get_device(name):
    """Get device by name"""
    response = requests.get(
        f"{NETBOX_API}/dcim/devices/",
        headers=headers,
        params={"name": name}
    )
    if response.status_code == 200:
        results = response.json().get("results", [])
        return results[0] if results else None
    return None

def get_device_role(name):
    """Get or create device role"""
    response = requests.get(
        f"{NETBOX_API}/dcim/device-roles/",
        headers=headers,
        params={"name": name}
    )
    if response.status_code == 200:
        results = response.json().get("results", [])
        if results:
            return results[0]
    
    # Create if not exists
    data = {"name": name, "slug": name.lower().replace(" ", "-"), "color": "000000"}
    response = requests.post(
        f"{NETBOX_API}/dcim/device-roles/",
        headers=headers,
        data=json.dumps(data)
    )
    if response.status_code == 201:
        return response.json()
    return None

def get_manufacturer(name):
    """Get or create manufacturer"""
    response = requests.get(
        f"{NETBOX_API}/dcim/manufacturers/",
        headers=headers,
        params={"name": name}
    )
    if response.status_code == 200:
        results = response.json().get("results", [])
        if results:
            return results[0]
    
    # Create if not exists
    data = {"name": name, "slug": name.lower()}
    response = requests.post(
        f"{NETBOX_API}/dcim/manufacturers/",
        headers=headers,
        data=json.dumps(data)
    )
    if response.status_code == 201:
        return response.json()
    return None

def get_device_type(manufacturer_name, model):
    """Get or create device type"""
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
    
    # Create if not exists
    data = {
        "manufacturer": manufacturer["id"],
        "model": model,
        "slug": model.lower().replace(" ", "-")
    }
    response = requests.post(
        f"{NETBOX_API}/dcim/device-types/",
        headers=headers,
        data=json.dumps(data)
    )
    if response.status_code == 201:
        return response.json()
    return None

def create_device(name, device_type_id, role_id, site_id, description="", status="active"):
    """Create a device"""
    data = {
        "name": name,
        "device_type": device_type_id,
        "role": role_id,
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

def create_ip_address(address, device_id=None):
    """Create an IP address"""
    data = {"address": address}
    
    if device_id:
        data["assigned_object_type"] = "dcim.device"
        data["assigned_object_id"] = device_id
    
    response = requests.post(
        f"{NETBOX_API}/ipam/ip-addresses/",
        headers=headers,
        data=json.dumps(data)
    )
    
    if response.status_code in [200, 201]:
        return response.json()
    else:
        print(f"Error creating IP {address}: {response.status_code}")
        return None

def get_ip_address(address):
    """Get IP address by address"""
    response = requests.get(
        f"{NETBOX_API}/ipam/ip-addresses/",
        headers=headers,
        params={"address": address}
    )
    if response.status_code == 200:
        results = response.json().get("results", [])
        return results[0] if results else None
    return None

def infer_manufacturer_from_mac(mac):
    """Infer manufacturer from MAC address"""
    mac = mac.lower().replace(":", "").replace("-", "")
    
    # Common OUI prefixes
    oui_map = {
        "00155d": "Microsoft",  # Hyper-V
        "000c29": "VMware",     # VMware
        "005056": "VMware",     # VMware
        "00089b": "Synology",   # QNAP/Synology
        "002324": "Lenovo",     # Lenovo
        "fc3fdb": "HP",         # HP
        "901b0e": "Dell",       # Dell
        "c03fd5": "Intel",      # NUC
        "8c8590": "Apple",      # MacBook
        "926825": "Unknown",    # Mobile
        "567593": "Apple",      # iPhone
        "dcb72e": "Xiaomi",     # Redmi
        "e03aaa": "Unknown",    # Unknown
        "94be46": "Unknown",    # Unknown
    }
    
    prefix = mac[:6]
    return oui_map.get(prefix, "Generic")

def infer_model_from_hostname(host):
    """Infer model from hostname"""
    host_lower = host.lower()
    
    if "macbook" in host_lower:
        return "MacBook Pro"
    elif "desktop" in host_lower:
        return "Desktop"
    elif "nuc" in host_lower:
        return "NUC"
    elif "nas" in host_lower or "synology" in host_lower:
        return "NAS"
    elif "virtual" in host_lower or "vm" in host_lower:
        return "Virtual Machine"
    elif "kubernetes" in host_lower:
        return "Server"
    elif "install" in host_lower:
        return "Virtual Machine"
    elif "suryendu" in host_lower or "gadget" in host_lower:
        return "Mobile Device"
    elif "iphone" in host_lower:
        return "iPhone"
    elif "redmi" in host_lower or "m2004" in host_lower:
        return "Smartphone"
    else:
        return "Unknown"

def clean_hostname(host):
    """Clean hostname for NetBox device name"""
    # Replace spaces and special characters
    name = host.replace("-", " ").replace("_", " ")
    # Remove duplicate spaces
    name = re.sub(r'\s+', ' ', name).strip()
    return name

def main():
    print("=" * 70)
    print("Updating NetBox from Vodafone Station Gateway Data")
    print("=" * 70)
    print()
    
    site = get_site()
    if not site:
        print("ERROR: Site not found!")
        return
    site_id = site["id"]
    print(f"✓ Site: {site['name']} (ID: {site_id})")
    print()
    
    # Get existing roles
    k3s_role = get_device_role("Worker")
    hypervisor_role = get_device_role("Hypervisor")
    nas_role = get_device_role("NAS")
    client_role = get_device_role("Client")
    vm_role = get_device_role("Virtual Machine")
    
    # Create new roles if needed
    mobile_role = get_device_role("Mobile")
    unknown_role = get_device_role("Unknown")
    control_plane_role = get_device_role("Control Plane")
    
    print("Roles:")
    print(f"  Worker: {k3s_role['id'] if k3s_role else 'NOT FOUND'}")
    print(f"  Hypervisor: {hypervisor_role['id'] if hypervisor_role else 'NOT FOUND'}")
    print(f"  NAS: {nas_role['id'] if nas_role else 'NOT FOUND'}")
    print(f"  Control Plane: {control_plane_role['id'] if control_plane_role else 'NOT FOUND'}")
    print()
    
    # Process active devices
    print("=" * 70)
    print("Processing ACTIVE Devices")
    print("=" * 70)
    print()
    
    active_stats = {"created": 0, "updated": 0, "skipped": 0, "errors": 0}
    
    for device_data in ACTIVE_DEVICES:
        host = device_data["host"]
        ip = device_data["ip"]
        mac = device_data["mac"]
        device_type = device_data["type"]
        category = device_data["category"]
        
        # Map to NetBox name
        netbox_name = NETBOX_NAME_MAPPINGS.get(host, clean_hostname(host))
        
        # Infer manufacturer and model
        manufacturer_name = infer_manufacturer_from_mac(mac)
        if not isinstance(manufacturer_name, str):
            manufacturer_name = "Generic"
        model = infer_model_from_hostname(host)
        
        # Map category to role
        role_map = {
            "K3s": control_plane_role if "NUC" in host or "kubernetes" in host else k3s_role,
            "Hypervisor": hypervisor_role,
            "NAS": nas_role,
            "VM": vm_role,
            "Mobile": mobile_role,
            "Laptop": client_role,
            "Unknown": unknown_role,
        }
        role = role_map.get(category, unknown_role)
        
        if not role:
            print(f"  ⚠ No role for category {category}, skipping {host}")
            active_stats["skipped"] += 1
            continue
        
        print(f"Processing {host} ({ip}) -> NetBox: {netbox_name}")
        
        # Check if device exists
        existing_device = get_device(netbox_name)
        
        if existing_device:
            # Update existing device
            device_id = existing_device["id"]
            update_data = {
                "description": f"{host} | MAC: {mac} | IP: {ip} | Type: {device_type}"
            }
            
            result = update_device(device_id, update_data)
            if result:
                print(f"  ✓ Updated device {netbox_name} (ID: {device_id})")
                active_stats["updated"] += 1
            else:
                print(f"  ✗ Failed to update device {netbox_name}")
                active_stats["errors"] += 1
        else:
            # Create new device
            manufacturer = get_manufacturer(manufacturer_name)
            if not manufacturer:
                print(f"  ✗ Manufacturer not found: {manufacturer_name}")
                active_stats["errors"] += 1
                continue
            
            device_type_obj = get_device_type(manufacturer_name, model)
            if not device_type_obj:
                print(f"  ✗ Device type not found: {manufacturer_name} {model}")
                active_stats["errors"] += 1
                continue
            
            description = f"{host} | MAC: {mac} | IP: {ip} | Type: {device_type} | Category: {category}"
            
            result = create_device(
                name=netbox_name,
                device_type_id=device_type_obj["id"],
                role_id=role["id"],
                site_id=site_id,
                description=description
            )
            
            if result:
                device_id = result["id"]
                print(f"  ✓ Created device {netbox_name} (ID: {device_id})")
                active_stats["created"] += 1
                
                # Create IP address
                ip_data = create_ip_address(f"{ip}/24", device_id)
                if ip_data:
                    print(f"    ✓ IP {ip} assigned")
                else:
                    print(f"    ⚠ IP {ip} creation failed")
            else:
                print(f"  ✗ Failed to create device {netbox_name}")
                active_stats["errors"] += 1
    
    print()
    print("Active Devices Summary:")
    print(f"  Created: {active_stats['created']}")
    print(f"  Updated: {active_stats['updated']}")
    print(f"  Skipped: {active_stats['skipped']}")
    print(f"  Errors: {active_stats['errors']}")
    print()
    
    # Process inactive devices
    print("=" * 70)
    print("Processing INACTIVE Devices")
    print("=" * 70)
    print()
    
    inactive_stats = {"created": 0, "updated": 0, "skipped": 0, "errors": 0}
    
    for device_data in INACTIVE_DEVICES:
        host = device_data["host"]
        ip = device_data["ip"]
        mac = device_data["mac"]
        device_type = device_data["type"]
        category = device_data["category"]
        
        # Map to NetBox name
        netbox_name = NETBOX_NAME_MAPPINGS.get(host, clean_hostname(host))
        
        # Infer manufacturer and model
        manufacturer_name = infer_manufacturer_from_mac(mac)
        if not isinstance(manufacturer_name, str):
            manufacturer_name = "Generic"
        model = infer_model_from_hostname(host)
        
        # Map category to role
        role_map = {
            "K3s": control_plane_role if "nuc" in host.lower() or "kubernetes" in host.lower() else k3s_role,
            "Hypervisor": hypervisor_role,
            "NAS": nas_role,
            "VM": vm_role,
            "Mobile": mobile_role,
            "Unknown": unknown_role,
        }
        role = role_map.get(category, unknown_role)
        
        if not role:
            print(f"  ⚠ No role for category {category}, skipping {host}")
            inactive_stats["skipped"] += 1
            continue
        
        print(f"Processing {host} ({ip}) -> NetBox: {netbox_name}")
        
        # Check if device exists
        existing_device = get_device(netbox_name)
        
        if existing_device:
            # Update existing device
            device_id = existing_device["id"]
            update_data = {
                "description": f"{host} | MAC: {mac} | IP: {ip} | Type: {device_type} | Status: INACTIVE",
                "status": "offline"
            }
            
            result = update_device(device_id, update_data)
            if result:
                print(f"  ✓ Updated device {netbox_name} (ID: {device_id})")
                inactive_stats["updated"] += 1
            else:
                print(f"  ✗ Failed to update device {netbox_name}")
                inactive_stats["errors"] += 1
        else:
            # Create new device
            manufacturer = get_manufacturer(manufacturer_name)
            if not manufacturer:
                print(f"  ✗ Manufacturer not found: {manufacturer_name}")
                inactive_stats["errors"] += 1
                continue
            
            device_type_obj = get_device_type(manufacturer_name, model)
            if not device_type_obj:
                print(f"  ✗ Device type not found: {manufacturer_name} {model}")
                inactive_stats["errors"] += 1
                continue
            
            description = f"{host} | MAC: {mac} | IP: {ip} | Type: {device_type} | Category: {category} | Status: INACTIVE"
            
            result = create_device(
                name=netbox_name,
                device_type_id=device_type_obj["id"],
                role_id=role["id"],
                site_id=site_id,
                description=description,
                status="offline"
            )
            
            if result:
                device_id = result["id"]
                print(f"  ✓ Created device {netbox_name} (ID: {device_id})")
                inactive_stats["created"] += 1
                
                # Create IP address
                ip_data = create_ip_address(f"{ip}/24", device_id)
                if ip_data:
                    print(f"    ✓ IP {ip} assigned")
                else:
                    print(f"    ⚠ IP {ip} creation failed")
            else:
                print(f"  ✗ Failed to create device {netbox_name}")
                inactive_stats["errors"] += 1
    
    print()
    print("Inactive Devices Summary:")
    print(f"  Created: {inactive_stats['created']}")
    print(f"  Updated: {inactive_stats['updated']}")
    print(f"  Skipped: {inactive_stats['skipped']}")
    print(f"  Errors: {inactive_stats['errors']}")
    print()
    
    # Overall summary
    total_created = active_stats["created"] + inactive_stats["created"]
    total_updated = active_stats["updated"] + inactive_stats["updated"]
    total_errors = active_stats["errors"] + inactive_stats["errors"]
    
    print("=" * 70)
    print("OVERALL SUMMARY")
    print("=" * 70)
    print(f"Total devices processed: {len(ACTIVE_DEVICES) + len(INACTIVE_DEVICES)}")
    print(f"  Active: {len(ACTIVE_DEVICES)}")
    print(f"  Inactive: {len(INACTIVE_DEVICES)}")
    print()
    print(f"Results:")
    print(f"  Devices created: {total_created}")
    print(f"  Devices updated: {total_updated}")
    print(f"  Devices skipped: {active_stats['skipped'] + inactive_stats['skipped']}")
    print(f"  Errors: {total_errors}")
    print()
    
    if total_errors == 0:
        print("✓ All devices processed successfully!")
    else:
        print(f"⚠ {total_errors} errors occurred")


if __name__ == "__main__":
    main()
