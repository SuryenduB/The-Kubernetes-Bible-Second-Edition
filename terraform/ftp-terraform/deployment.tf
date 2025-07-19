resource "kubernetes_deployment_v1" "ftp_deploy" {
  metadata {
    name   = "ftp-server"
    labels = { app = "ftp" }
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "ftp" } }
    template {
      metadata { labels = { app = "ftp" } }
      spec {
        container {
          name  = "ftp"
          image = "atmoz/ftp"
          env {
            name = "FTP_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.ftp_secret.metadata[0].name
                key  = "FTP_USER"
              }
            }
          }
          env {
            name = "FTP_PASS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.ftp_secret.metadata[0].name
                key  = "FTP_PASS"
              }
            }
          }
          port { container_port = 21 }
          port { container_port = 30000 }
          port { container_port = 30001 }
          volume_mount {
            name       = "ftp-volume"
            mount_path = "/home"
          }
        }
        volume {
          name = "ftp-volume"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.ftp_pvc.metadata[0].name
          }
        }
      }
    }
  }
  depends_on = [kubernetes_persistent_volume_claim.ftp_pvc]
}
