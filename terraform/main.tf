provider "kubernetes" {
  config_path = "~/.kube/config" # Update path if needed
}


resource "kubernetes_namespace" "example" {
  metadata {
    name = "ai"
  }
}

# PVC for Ollama
resource "kubernetes_persistent_volume_claim" "ollama_pvc" {
  metadata {
    name      = "ollama-pvc"
    namespace = kubernetes_namespace.example.metadata[0].name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "local-path"
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
    name      = "webui-pvc"
    namespace = kubernetes_namespace.example.metadata[0].name
  }
  spec {
    storage_class_name = "local-path"
    access_modes       = ["ReadWriteOnce"]
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
    labels = {
      "app" = "ollama"
    }
    namespace = kubernetes_namespace.example.metadata[0].name
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
          liveness_probe {
            http_get {
              path = "/v1/models"
              port = 11434
            }
            initial_delay_seconds = 10
            period_seconds        = 10
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
    namespace = kubernetes_namespace.example.metadata[0].name
  }
  spec {
    selector = {
      app = kubernetes_deployment.ollama.metadata[0].labels["app"]
    }
    session_affinity = "ClientIP"
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
    name      = "openwebui"
    namespace = kubernetes_namespace.example.metadata[0].name
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
          app       = "openwebui"
          namespace = kubernetes_namespace.example.metadata[0].name
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
    name      = "openwebui"
    namespace = kubernetes_namespace.example.metadata[0].name
  }
  spec {
    selector = {
      app = "openwebui"
    }
    port {
      port        = 8080
      target_port = 8080
    }
    type = "ClusterIP"
  }
}

# Ingress: OpenWebUI
resource "kubernetes_ingress_v1" "openwebui_ingress" {
  metadata {
    name      = "openwebui-ingress"
    namespace = kubernetes_namespace.example.metadata[0].name
    annotations = {
      "kubernetes.io/ingress.class"                      = "traefik"
      "traefik.ingress.kubernetes.io/router.entrypoints" = "web"
      #"traefik.ingress.kubernetes.io/router.middlewares" = "ai-strip-ai-prefix@kubernetescrd"
    }
  }

  spec {
    ingress_class_name = "traefik"


    rule {
      host = "openwebui.local" # Update with your domain or IP`
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.openwebui.metadata[0].name
              port {
                number = 8080
              }
            }
          }
        }
      }

    }
  }
}



