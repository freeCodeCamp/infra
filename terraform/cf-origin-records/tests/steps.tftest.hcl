mock_provider "cloudflare" {}

override_data {
  target = data.terraform_remote_state.stg
  values = {
    outputs = {
      nodes = {
        "stg-vm-pxy-1" = { id = "a", role = "pxy", main_ip = "198.51.100.1" }
        "stg-vm-pxy-2" = { id = "b", role = "pxy", main_ip = "198.51.100.2" }
        "stg-vm-pxy-3" = { id = "c", role = "pxy", main_ip = "198.51.100.3" }
        "stg-vm-api-1" = { id = "d", role = "api", main_ip = "198.51.100.9" }
      }
    }
  }
}

override_data {
  target = data.terraform_remote_state.prd
  values = {
    outputs = {
      nodes = {
        "prd-vm-pxy-1" = { id = "a", role = "pxy", main_ip = "203.0.113.1" }
        "prd-vm-pxy-2" = { id = "b", role = "pxy", main_ip = "203.0.113.2" }
        "prd-vm-pxy-3" = { id = "c", role = "pxy", main_ip = "203.0.113.3" }
        "prd-vm-api-1" = { id = "d", role = "api", main_ip = "203.0.113.9" }
      }
    }
  }
}

variables {
  state_passphrase = "test-passphrase-with-32-characters"
  zone_ids         = { stg = "zone-stg", prd = "zone-prd" }
  linode_origin_ips = {
    stg = ["192.0.2.100"]
    prd = ["192.0.2.1", "192.0.2.2", "192.0.2.3"]
  }
}

run "linode_step_holds_only_the_linode_records" {
  command = plan

  assert {
    condition     = length(cloudflare_dns_record.origin) == 27
    error_message = "Expected the 27 Linode records."
  }
  assert {
    condition     = output.records["www.freecodecamp.org"] == ["192.0.2.1", "192.0.2.2", "192.0.2.3"]
    error_message = "www must hold the 3 Linode records."
  }
  assert {
    condition     = output.records["medium.freecodecamp.org"] == ["192.0.2.1"]
    error_message = "medium must hold its one Linode record."
  }
  assert {
    condition     = output.records["www.freecodecamp.dev"] == ["192.0.2.100"]
    error_message = "staging www must hold its one Linode record."
  }
}

run "production_25_adds_one_vultr_record_to_the_three_record_hostnames" {
  command = plan

  variables {
    prd_step = "25"
  }

  assert {
    condition     = output.records["www.freecodecamp.org"] == ["192.0.2.1", "192.0.2.2", "192.0.2.3", "203.0.113.1"]
    error_message = "www must hold 3 Linode records and 1 Vultr record."
  }
  assert {
    condition     = output.records["medium.freecodecamp.org"] == ["192.0.2.1"]
    error_message = "A one-record hostname stays on Linode at 25."
  }
  assert {
    condition     = output.records["www.freecodecamp.dev"] == ["192.0.2.100"]
    error_message = "The production step must not move staging."
  }
}

run "production_50_balances_the_records" {
  command = plan

  variables {
    prd_step = "50"
  }

  assert {
    condition     = output.records["api.freecodecamp.org"] == ["192.0.2.1", "192.0.2.2", "192.0.2.3", "203.0.113.1", "203.0.113.2", "203.0.113.3"]
    error_message = "api must hold 3 Linode records and 3 Vultr records."
  }
  assert {
    condition     = output.records["news.freecodecamp.org"] == ["192.0.2.1", "203.0.113.1"]
    error_message = "A one-record hostname must hold 1 Linode record and 1 Vultr record."
  }
}

run "production_100_holds_only_the_vultr_records" {
  command = plan

  variables {
    prd_step = "100"
  }

  assert {
    condition     = output.records["freecodecamp.org"] == ["203.0.113.1", "203.0.113.2", "203.0.113.3"]
    error_message = "The apex must hold only the 3 Vultr records."
  }
  assert {
    condition     = output.records["blog.freecodecamp.org"] == ["203.0.113.1", "203.0.113.2", "203.0.113.3"]
    error_message = "A one-record hostname must hold only the 3 Vultr records."
  }
}

run "staging_steps_use_staging_addresses" {
  command = plan

  variables {
    stg_step = "50"
  }

  assert {
    condition     = output.records["api.freecodecamp.dev"] == ["192.0.2.100", "198.51.100.1"]
    error_message = "Staging 50 must hold 1 Linode record and 1 Vultr record."
  }
}

run "staging_rejects_the_25_step" {
  command = plan

  variables {
    stg_step = "25"
  }

  expect_failures = [var.stg_step]
}

run "records_are_proxied_and_in_the_right_zone" {
  command = plan

  assert {
    condition     = cloudflare_dns_record.origin["www.freecodecamp.org/linode-1"].proxied == true
    error_message = "Records must be proxied."
  }
  assert {
    condition     = cloudflare_dns_record.origin["www.freecodecamp.org/linode-1"].zone_id == "zone-prd"
    error_message = "A production record must be in the production zone."
  }
  assert {
    condition     = cloudflare_dns_record.origin["freecodecamp.dev/linode-1"].zone_id == "zone-stg"
    error_message = "A staging record must be in the staging zone."
  }
}

run "a_proxy_marked_down_loses_its_records" {
  command = plan

  variables {
    prd_step     = "100"
    proxies_down = ["prd-vm-pxy-2"]
  }

  assert {
    condition     = output.records["www.freecodecamp.org"] == ["203.0.113.1", "203.0.113.3"]
    error_message = "www must drop the record of the proxy marked down."
  }
  assert {
    condition     = contains(keys(cloudflare_dns_record.origin), "www.freecodecamp.org/prd-vm-pxy-3")
    error_message = "A record must keep its key when another proxy goes down."
  }
}

run "all_proxies_marked_down_stops_the_plan" {
  command = plan

  variables {
    prd_step     = "100"
    proxies_down = ["prd-vm-pxy-1", "prd-vm-pxy-2", "prd-vm-pxy-3"]
  }

  expect_failures = [terraform_data.guard]
}

run "down_names_cannot_stand_in_for_missing_proxies" {
  command = plan

  variables {
    prd_step     = "100"
    proxies_down = ["prd-vm-pxy-2", "prd-vm-pxy-3"]
  }

  override_data {
    target = data.terraform_remote_state.prd
    values = {
      outputs = {
        nodes = {
          "prd-vm-pxy-1" = { id = "a", role = "pxy", main_ip = "203.0.113.1" }
        }
      }
    }
  }

  expect_failures = [terraform_data.guard]
}

run "a_down_name_outside_the_fleet_stops_the_plan" {
  command = plan

  variables {
    prd_step     = "100"
    proxies_down = ["prd-vm-pxy-9"]
  }

  expect_failures = [terraform_data.guard]
}

run "a_down_name_that_is_not_a_proxy_is_rejected" {
  command = plan

  variables {
    prd_step     = "100"
    proxies_down = ["prd-vm-api-1"]
  }

  expect_failures = [var.proxies_down]
}

run "fleet_with_a_missing_proxy_stops_the_plan" {
  command = plan

  variables {
    prd_step = "100"
  }

  override_data {
    target = data.terraform_remote_state.prd
    values = {
      outputs = {
        nodes = {
          "prd-vm-pxy-1" = { id = "a", role = "pxy", main_ip = "203.0.113.1" }
        }
      }
    }
  }

  expect_failures = [terraform_data.guard]
}
