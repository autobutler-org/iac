# This repo is greenfield, so the gate starts strict and stays strict. The rules the
# upstream config this was seeded from had to disable -- undocumented variables and
# outputs, unused declarations, missing version constraints -- were all concessions to a
# pre-existing tree. There is nothing here to grandfather in, and a rule that is cheap to
# satisfy on the first file is expensive to retrofit on the hundredth.

plugin "terraform" {
    version = "0.15.0"
    source  = "github.com/terraform-linters/tflint-ruleset-terraform"
    enabled = true
    preset  = "all"
}

# Azure-specific rules: deprecated azurerm arguments, invalid SKU and location strings,
# required-argument checks the provider only reports at apply time.
plugin "azurerm" {
    version = "0.32.0"
    source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
    enabled = true
}

rule "terraform_deprecated_interpolation" {
    enabled = true
}

rule "terraform_naming_convention" {
    enabled = true
}
