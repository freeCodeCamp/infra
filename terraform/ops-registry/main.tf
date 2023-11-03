locals {
  repositories = {
    # Operations
    ops_test = { name = "ops/test" },

    # Production
    prd_mobile_api = { name = "org/mobile-api" },

    prd_eng = { name = "org/news-english" },
    prd_chn = { name = "org/news-chinese" },
    prd_esp = { name = "org/news-espanol" },
    prd_ita = { name = "org/news-italian" },
    prd_jpn = { name = "org/news-japanese" },
    prd_kor = { name = "org/news-korean" },
    prd_por = { name = "org/news-portuguese" },
    prd_ukr = { name = "org/news-ukrainian" },

    # Staging
    stg_mobile_api = { name = "dev/mobile-api" },

    stg_eng = { name = "dev/news-english" },
    stg_chn = { name = "dev/news-chinese" },
    stg_esp = { name = "dev/news-espanol" },
    stg_ita = { name = "dev/news-italian" },
    stg_jpn = { name = "dev/news-japanese" },
    stg_kor = { name = "dev/news-korean" },
    stg_por = { name = "dev/news-portuguese" },
    stg_ukr = { name = "dev/news-ukrainian" },

    # Old backups
    bck_ara = { name = "rtd/news-arabic" },
    bck_ben = { name = "rtd/news-bengali" },
    bck_fre = { name = "rtd/news-french" },
    bck_ger = { name = "rtd/news-german" },
    bck_ind = { name = "rtd/news-indonesian" },
    bck_swa = { name = "rtd/news-swahili" },
    bck_urd = { name = "rtd/news-urdu" },
  }
}

resource "aws_ecr_repository" "ecr_repositories" {
  for_each = local.repositories

  name                 = each.value.name
  image_tag_mutability = "MUTABLE"
}
