# How to Manage K3s Homelab Cluster Power

This guide walks you through safely starting and shutting down the K3s homelab cluster. It covers secure password management, non-interactive remote commands, and executing tasks in the background without terminal suspension.

---

## Prerequisites

Before executing power management scripts, ensure your orchestration host (e.g., your local machine) has the necessary modules and utilities installed.

### 1. Install PowerShell SecretStore Modules
To securely store passwords without hardcoding them in scripts, install the Microsoft SecretManagement modules:
```powershell
# Install modules globally
Install-Module -Name Microsoft.PowerShell.SecretManagement -Scope CurrentUser -Force
Install-Module -Name Microsoft.PowerShell.SecretStore -Scope CurrentUser -Force
```

### 2. Install sshpass
For non-interactive SSH password authentication in background tasks, install `sshpass` on your host:
* **macOS (via Homebrew):**
  ```bash
  brew install hudochenkov/sshpass/sshpass
  ```
* **Debian/Ubuntu:**
  ```bash
  sudo apt-get install -y sshpass
  ```

---

## Step 1: Secure Credential Setup

Rather than using plaintext credential files (`cred.xml`), the scripts are configured to retrieve credentials from the PowerShell SecretStore.

### 1. Configure the SecretStore for Non-Interactive Automation
Run the following command to allow background scripts to retrieve secrets without prompting for a master vault password:
```powershell
Set-SecretStoreConfiguration -Authentication None -Interaction None -Confirm:$false
```

### 2. Register the Sudo Password
Store your homelab sudo password (`558068`) under the secret key `k3s-homelab-sudo`:
```powershell
# Store the password securely in the default LocalStore vault
Set-Secret -Name "k3s-homelab-sudo" -Secret "558068"
```

---

## Step 2: How to Start the Cluster

To boot all nodes and wait for the Kubernetes control plane to converge:

1. Execute the start script:
   ```powershell
   pwsh -File WindowsLab/Start-K3sHomelab.ps1
   ```
2. Monitor node convergence:
   ```bash
   kubectl get nodes -w
   ```
3. Verify that all system pods are running:
   ```bash
   kubectl get pods -A
   ```

---

## Step 3: How to Stop the Cluster Gracefully

Shutting down the cluster systematically cordons and drains the nodes (migrating active workloads and respecting Pod Disruption Budgets) before sending a remote `poweroff` instruction.

### 1. Run the Shutdown Script in the Background
Because draining nodes and ssh timeouts can take several minutes, run the command in the background. 

> [!IMPORTANT]
> To prevent the background job from being suspended by the OS shell (Job Control `SIGTTIN`/`SIGTTOU` signals), you **must** redirect stdout/stderr to a log file and stdin from `/dev/null`:

```bash
pwsh -File WindowsLab/shutdown_homelab.ps1 -Force > shutdown.log 2>&1 < /dev/null &
```

### 2. Monitor Shutdown Progress
Follow the logs in real-time to track node cordoning, pod eviction, and power-off sequences:
```bash
tail -f shutdown.log
```

---

## Technical Details & Troubleshooting

### Cross-Platform Marshaling Support
When retrieving secrets from the SecretStore on non-Windows hosts, standard `.NET` marshaling using `PtrToStringAuto` can truncate UTF-16 strings because of Unix-specific null-byte string terminators. The power scripts solve this by forcing UTF-16 decoding using `PtrToStringUni`:
```powershell
$plainPass = [System.Runtime.InteropServices.Marshal]::PtrToStringUni(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
)
```

### Non-Interactive SSH Failures
If you see connection errors or password prompts in `shutdown.log`, verify that `sshpass` is accessible in your shell's `PATH`. The scripts automatically fall back to standard `ssh` if `sshpass` is missing, which will require an interactive terminal.
