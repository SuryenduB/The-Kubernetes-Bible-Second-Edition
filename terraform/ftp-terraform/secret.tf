resource "random_password" "ftp_password" {
  length           = 16
  special          = true
  override_special = "!@#$%&" 
}

resource "kubernetes_secret" "ftp_secret" {
  metadata {
    name = "ftp-secret"
  }
  data = {
    FTP_USER = var.ftp_user
    FTP_PASS = random_password.ftp_password.result
  }
}