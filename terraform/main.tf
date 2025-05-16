provider "kubernetes" {
  config_path = "~/.kube/config" # Update path if needed
}

# PVC for Ollama
resource "kubernetes_persistent_volume_claim" "ollama_pvc" {
  metadata {
    name = "ollama-pvc"
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
  wait_until_bound = false

}

# PVC for WebUI
resource "kubernetes_persistent_volume_claim" "webui_pvc" {
  metadata {
    name = "webui-pvc"
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
  wait_until_bound = false

}

# Deployment: Ollama
resource "kubernetes_deployment" "ollama" {
  metadata {
    name = "ollama"
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
          name  = "ollama"
          image = "ollama/ollama"
          port {
            container_port = 11434
          }
          volume_mount {
            name       = "ollama-storage"
            mount_path = "/root/.ollama"
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
    name = "ollama"
  }
  spec {
    selector = {
      app = "ollama"
    }
    port {
      port        = 11434
      target_port = 11434
    }
    type = "ClusterIP"
  }
}

# Deployment: OpenWebUI
resource "kubernetes_deployment" "openwebui" {
  metadata {
    name = "openwebui"
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
          name  = "openwebui"
          image = "ghcr.io/open-webui/open-webui"
          port {
            container_port = 8080
          }
          env {
            name  = "OLLAMA_BASE_URL"
            value = "http://ollama:11434"
          }
          volume_mount {
            name       = "webui-storage"
            mount_path = "/app/data"
          }
        }
        volume {
          name = "webui-storage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.webui_pvc.metadata[0].name
          }
        }
      }
    }
  }
}

# Service: OpenWebUI
resource "kubernetes_service" "openwebui" {
  metadata {
    name = "openwebui"
  }
  spec {
    selector = {
      app = "openwebui"
    }
    port {
      port        = 3000
      target_port = 8080
    }
    type = "ClusterIP"
  }
}

# Ingress: OpenWebUI
resource "kubernetes_ingress_v1" "openwebui_ingress" {
  metadata {
    name = "openwebui-ingress"
    annotations = {
      "kubernetes.io/ingress.class"     = "traefik"
      "traefik.ingress.kubernetes.io/router.middlewares" = "kube-system-strip-ai@kubernetescrd"
    }
  }

  spec {
    ingress_class_name = "traefik"
    

    rule {
      host = "openwebui.local" # Update with your domain
      http {
        path {
          path      = "/ai"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.openwebui.metadata[0].name
              port {
                number = 3000
              }
            }
          }
        }
      }
    }
  }
}

# Middleware: Strip Prefix
resource "kubernetes_manifest" "strip_ai_middleware" {
  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"

    metadata = {
      name      = "strip-ai"
      namespace = "kube-system"
    }
    spec = {
      stripPrefix = {
        prefixes = ["/ai"]
      }
    }
  }
}
