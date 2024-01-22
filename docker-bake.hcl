variable "TAG" {
  default = "loongarch64_other_arch"
}

group "default" {
  targets = ["default"]
}

target "default" {
  dockerfile = "Dockerfile"
  tags = ["cr.loongnix.cn/tonistiigi/binfmt:${TAG}"]
  #tags = ["qemu:bin"]
} 
