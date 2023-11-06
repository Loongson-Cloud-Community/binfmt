variable "TAG" {
  default = "latest"
}

group "default" {
  targets = ["hello"]
}

target "hello" {
  #args={
  #      HTTP_PROXY= "http://10.130.0.20:7890",
  #      HTTPS_PROXY= "http://10.130.0.20:7890",
  #}
  dockerfile = "Dockerfile"
  #tags = ["binfmt:${TAG}"]
  tags = ["lcr.loongnix.cn/library/tonistiigi/binfmt:${TAG}"]
} 
