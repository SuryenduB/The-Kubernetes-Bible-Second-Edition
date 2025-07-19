resource "kubernetes_service" "ftp_service" {
  metadata { name = "ftp-service" }
  spec {
    type     = "NodePort"
    selector = { app = "ftp" }
    port {
      name        = "ftp"
      port        = 21
      target_port = 21
      node_port   = 30211
    }
    port {
      name        = "passive1"
      port        = 30000
      target_port = 30000
      node_port   = 30300
    }
    port {
      name        = "passive2"
      port        = 30001
      target_port = 30001
      node_port   = 30301
    }
  }
}
