client {
  enabled = true
  meta {
    role = "worker-stateless"
  }
}

server {
  enabled          = true
  bootstrap_expect = 1
}
