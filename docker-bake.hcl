variable "TAG" {
  default = "latest"
}

group "default" {
  targets = ["default"]
}

target "default" {
  dockerfile = "Dockerfile"
  tags = ["lcr.loongnix.cn/tonistiigi/binfmt:${TAG}"]
} 
