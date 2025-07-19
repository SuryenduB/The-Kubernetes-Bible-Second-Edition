resource "kubernetes_persistent_volume_claim" "ftp_pvc" {
  metadata {
    name = "ftp-pvc"
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = var.ftp_storage_size
      }
    }
    storage_class_name = "local-path"
  }
}