provider "kubernetes" {
  config_path = "~/.kube/config"
}

# Environment Variables
locals {
  ollama_image       = "ollama/ollama:latest"
  openwebui_image    = "ghcr.io/open-webui/open-webui:main"
  ollama_port        = 11434
  openwebui_port     = 8080
  exposed_webui_port = 3000
}

# PVC for Ollama
resource "kubernetes_persistent_volume_claim" "ollama_pvc" {
  metadata {
    name      = "ollama-pvc"
    namespace = "default"
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
    storage_class_name = "local-path"
  }
  wait_until_bound = false
}

# PVC for OpenWebUI
resource "kubernetes_persistent_volume_claim" "openwebui_pvc" {
  metadata {
    name      = "openwebui-pvc"
    namespace = "default"
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
    storage_class_name = "local-path"
  }
  wait_until_bound = false
}

# Deployment: Ollama
resource "kubernetes_deployment" "ollama" {
  metadata {
    name      = "ollama"
    namespace = "default"
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "ollama"
      }
    }
    template {
      metadata {
        labels = {
          app = "ollama"
        }
      }
      spec {
        container {
          name            = "ollama"
          image           = local.ollama_image
          image_pull_policy = "Always"
          tty             = true
          port {
            container_port = local.ollama_port
          }
          volume_mount {
            name       = "ollama-storage"
            mount_path = "/root/.ollama"
          }
          resources {
            limits = {
              cpu    = "2"
              memory = "4Gi"
            }
            requests = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }
        }
        volume {
          name = "ollama-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.ollama_pvc.metadata[0].name
          }
        }
      }
    }
  }
}

# Service: Ollama
resource "kubernetes_service" "ollama" {
  metadata {
    name      = "ollama"
    namespace = "default"
  }
  spec {
    selector = {
      app = "ollama"
    }
    port {
      port        = local.ollama_port
      target_port = local.ollama_port
    }
    type = "ClusterIP"
  }
}

# Deployment: OpenWebUI
resource "kubernetes_deployment" "openwebui" {
  metadata {
    name      = "openwebui"
    namespace = "default"
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "openwebui"
      }
    }
    template {
      metadata {
        labels = {
          app = "openwebui"
        }
      }
      spec {
        container {
          name            = "openwebui"
          image           = local.openwebui_image
          image_pull_policy = "Always"
          tty             = true
          
          port {
            container_port = local.openwebui_port
          }
          env {
            name  = "OLLAMA_BASE_URL"
            value = "http://ollama.default.svc.cluster.local:11434"
          }
          env {
            name  = "WEBUI_SECRET_KEY"
            value = ""
          }
          volume_mount {
            name       = "webui-storage"
            mount_path = "/app/backend/data"
          }
          resources {
            limits = {
              cpu    = "1"
              memory = "2Gi"
            }
            requests = {
              cpu    = "250m"
              memory = "512Mi"
            }
          }
        }
        volume {
          name = "webui-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.openwebui_pvc.metadata[0].name
          }
        }
      }
    }
  }
}

# Service: OpenWebUI
resource "kubernetes_service" "openwebui" {
  metadata {
    name      = "openwebui"
    namespace = "default"
  }
  spec {
    selector = {
      app = "openwebui"
    }
    port {
      name        = "http"
      port        = local.exposed_webui_port
      target_port = local.openwebui_port
    }
    type = "LoadBalancer"
  }
}