# Kubernetes Manifests for Multi-Node K3s Cluster

This directory contains Kubernetes manifests for deploying a multi-node K3s cluster based on the provided `docker-compose.yml` file. The manifests are organized into logical files for each service type, ensuring clarity and ease of management.

## Directory Structure

- **base/**: Contains individual YAML files for each service, including Deployments, Services, and Jobs.
- **kustomization.yaml**: A Kustomization file that aggregates all resources for deployment.

## Services Included

1. **ActiveMQ**
   - Deployment: `activemq-deployment.yaml`
   - Service: `activemq-service.yaml`

2. **Counter**
   - Deployment: `counter-deployment.yaml`
   - Service: `counter-service.yaml`

3. **MySQL**
   - Deployment: `db-mysql-deployment.yaml`
   - Service: `db-mysql-service.yaml`

4. **MSSQL**
   - Deployment: `db-mssql-deployment.yaml`
   - Service: `db-mssql-service.yaml`

5. **SailPoint IdentityIQ**
   - Deployment: `iiq-deployment.yaml`
   - Service: `iiq-service.yaml`
   - Initialization Job: `iiq-init-job.yaml`

6. **OpenLDAP**
   - Deployment: `ldap-deployment.yaml`
   - Service: `ldap-service.yaml`

7. **Traefik (Load Balancer)**
   - Deployment: `loadbalancer-deployment.yaml`
   - Service: `loadbalancer-service.yaml`

8. **MailHog**
   - Deployment: `mail-deployment.yaml`
   - Service: `mail-service.yaml`

9. **phpLDAPadmin**
   - Deployment: `phpldapadmin-deployment.yaml`
   - Service: `phpldapadmin-service.yaml`

10. **SSH Server**
    - Deployment: `ssh-deployment.yaml`
    - Service: `ssh-service.yaml`

## Deployment Instructions

1. **Install K3s**: Follow the official K3s installation guide to set up your cluster.

2. **Apply Manifests**: Use the following command to apply all manifests:
   ```
   kubectl apply -k ./whoami-manifests
   ```

3. **Verify Deployments**: Check the status of your deployments with:
   ```
   kubectl get all
   ```

4. **Access Services**: Depending on your service type (ClusterIP, NodePort), access the services as needed.

## Configuration

- Modify environment variables in the respective deployment files as necessary to suit your configuration needs.
- Ensure that PersistentVolumeClaims are properly configured for stateful services like MySQL and MSSQL.

This README serves as a guide for deploying and managing the services defined in the Kubernetes manifests. For further customization, refer to the individual service YAML files.