output "records" {
  description = "Addresses for each hostname at the current steps, Linode first."
  value = {
    for host in distinct([for record in values(local.records) : record.host]) : host => concat(
      [for key in sort(keys(local.records)) : local.records[key].content if local.records[key].host == host && strcontains(key, "/linode-")],
      [for key in sort(keys(local.records)) : local.records[key].content if local.records[key].host == host && !strcontains(key, "/linode-")],
    )
  }
}
