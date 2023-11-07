variable "TAG" {
  #default = "latest"
  # default = "openeuler-qemu-8.2.0-rc2"
  default = "openeuler-qemu-7.2.6"
}

group "default" {
  targets = ["default"]
}

target "default" {
  #dockerfile = "Dockerfile"
  dockerfile = "Dockerfile.local" 
  tags = ["lcr.loongnix.cn/tonistiigi/binfmt:${TAG}"]
} 
