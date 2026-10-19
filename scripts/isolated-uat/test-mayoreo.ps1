$ErrorActionPreference = "Stop"

. "$PSScriptRoot\_common.ps1"

Assert-IsolatedEnvironment
Write-IsolatedBanner

$base = "http://127.0.0.1:$ApiPort"
$run = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

function Invoke-UatApi {
  param(
    [Parameter(Mandatory = $true)][string]$Method,
    [Parameter(Mandatory = $true)][string]$Path,
    [object]$Body = $null,
    [string]$Token = $null,
    [int]$ExpectedError = 0
  )

  $headers = @{}
  if ($Token) {
    $headers.Authorization = "Bearer $Token"
  }

  try {
    $params = @{
      Method = $Method
      Uri = "$base$Path"
      Headers = $headers
      ContentType = "application/json"
    }
    if ($null -ne $Body) {
      $params.Body = ($Body | ConvertTo-Json -Depth 20)
    }
    $response = Invoke-RestMethod @params
    if ($ExpectedError -ge 400) {
      throw "Expected HTTP $ExpectedError but request succeeded: $Method $Path"
    }
    return $response
  } catch {
    $response = $_.Exception.Response
    if ($response -and $ExpectedError -ge 400 -and [int]$response.StatusCode -eq $ExpectedError) {
      return [pscustomobject]@{ expectedError = $ExpectedError; path = $Path }
    }
    throw
  }
}

function New-UatCompany {
  param([Parameter(Mandatory = $true)][string]$Suffix)

  $taxId = if ($Suffix -eq "a") { "121212121" } else { "232323232" }
  return Invoke-UatApi POST "/auth/register-business" @{
    firstName = "Mayoreo"
    lastName = $Suffix
    email = "mayoreo-$run-$Suffix@example.test"
    phone = "8095550000"
    password = "MayoreoE2E123!"
    confirmPassword = "MayoreoE2E123!"
    commercialName = "Mayoreo UAT $Suffix $run"
    taxId = $taxId
    businessPhone = "8095551111"
    address = "UAT Mayoreo"
    country = "DO"
  }
}

$companyA = New-UatCompany "a"
$companyB = New-UatCompany "b"
$tokenA = $companyA.accessToken
$tokenB = $companyB.accessToken

$settingsOff = Invoke-UatApi GET "/settings" -Token $tokenA
if ($settingsOff.wholesalePriceListsEnabled -ne $false) {
  throw "Feature flag must be false by default."
}

$productA1 = Invoke-UatApi POST "/products" @{
  nombre = "Cable UAT $run"
  codigo = "MY-$run-A1"
  categoria = "Mayoreo"
  precio = 100
  costo = 40
  trackInventory = $false
} $tokenA
$productA2 = Invoke-UatApi POST "/products" @{
  nombre = "Switch UAT $run"
  codigo = "MY-$run-A2"
  categoria = "Mayoreo"
  precio = 200
  costo = 80
  trackInventory = $false
} $tokenA
$productB = Invoke-UatApi POST "/products" @{
  nombre = "Otro tenant $run"
  codigo = "MY-$run-B"
  categoria = "Mayoreo"
  precio = 300
  costo = 120
  trackInventory = $false
} $tokenB

$disabledResolution = Invoke-UatApi POST "/price-lists/resolve-line" @{
  productId = $productA1.id
  qty = 3
} $tokenA
if ($disabledResolution.applied -ne $false -or $disabledResolution.reason -ne "MODULE_DISABLED") {
  throw "Disabled module should not apply price list."
}

Invoke-UatApi PATCH "/settings" @{ wholesalePriceListsEnabled = $true } $tokenA | Out-Null
Invoke-UatApi PATCH "/settings" @{ wholesalePriceListsEnabled = $true } $tokenB | Out-Null

$list = Invoke-UatApi POST "/price-lists" @{
  name = "Mayorista UAT $run"
  priority = 10
} $tokenA

Invoke-UatApi POST "/price-lists/$($list.id)/rules" @{
  productId = $productA1.id
  mode = "FIXED_PRICE"
  fixedPrice = 80
  minQuantity = 1
  tiers = @(@{ minQuantity = 5; mode = "FIXED_PRICE"; fixedPrice = 70 })
} $tokenA | Out-Null

Invoke-UatApi POST "/price-lists/$($list.id)/rules" @{
  productId = $productA2.id
  mode = "PERCENT_DISCOUNT"
  discountPercent = 10
  minQuantity = 1
  tiers = @(@{ minQuantity = 3; mode = "PERCENT_DISCOUNT"; discountPercent = 25 })
} $tokenA | Out-Null

$client = Invoke-UatApi POST "/clients" @{
  nombre = "Cliente Mayorista $run"
  telefono = "8095553333"
} $tokenA
Invoke-UatApi PATCH "/price-lists/clients/$($client.id)" @{ priceListId = $list.id } $tokenA | Out-Null

$fixed = Invoke-UatApi POST "/price-lists/resolve-line" @{
  productId = $productA1.id
  qty = 2
  clientId = $client.id
} $tokenA
if ($fixed.applied -ne $true -or [decimal]$fixed.unitPrice -ne 80) {
  throw "Fixed price did not apply."
}

$fixedTier = Invoke-UatApi POST "/price-lists/resolve-line" @{
  productId = $productA1.id
  qty = 6
  clientId = $client.id
} $tokenA
if ([decimal]$fixedTier.unitPrice -ne 70) {
  throw "Quantity fixed tier did not apply."
}

$discountTier = Invoke-UatApi POST "/price-lists/resolve-line" @{
  productId = $productA2.id
  qty = 4
  priceListId = $list.id
} $tokenA
if ([decimal]$discountTier.unitPrice -ne 150) {
  throw "Percent discount tier did not apply."
}

Invoke-UatApi POST "/price-lists/resolve-line" @{
  productId = $productA1.id
  qty = 1
  priceListId = $list.id
} $tokenB -ExpectedError 400 | Out-Null

Invoke-UatApi PATCH "/price-lists/$($list.id)" @{ active = $false } $tokenA | Out-Null
Invoke-UatApi POST "/price-lists/resolve-line" @{
  productId = $productA1.id
  qty = 1
  clientId = $client.id
} $tokenA -ExpectedError 400 | Out-Null
Invoke-UatApi PATCH "/price-lists/$($list.id)" @{ active = $true } $tokenA | Out-Null

$cash = Invoke-UatApi POST "/cash/sessions/open" @{
  openingAmount = 0
  deviceFingerprint = "uat-$run"
} $tokenA
$sale = Invoke-UatApi POST "/sales" @{
  paymentMethod = "cash"
  paymentCashAmount = 420
  cashReceived = 420
  expectedTotalSold = 420
  originCashSessionId = $cash.shiftId
  deviceFingerprint = "uat-$run"
  customerId = $client.id
  items = @(@{ productId = $productA1.id; qty = 6; priceSoldUnit = 70 })
} $tokenA
if ($sale.priceListId -ne $list.id) {
  throw "Sale price list snapshot missing."
}
if (-not ($sale.items | Where-Object { $_.appliedPriceListId -eq $list.id -and [decimal]$_.priceSoldUnit -eq 70 })) {
  throw "Sale item snapshot missing."
}

Invoke-UatApi POST "/sales" @{
  paymentMethod = "cash"
  paymentCashAmount = 999
  cashReceived = 999
  expectedTotalSold = 999
  originCashSessionId = $cash.shiftId
  deviceFingerprint = "uat-$run"
  customerId = $client.id
  items = @(@{ productId = $productA1.id; qty = 2; priceSoldUnit = 999 })
} $tokenA -ExpectedError 400 | Out-Null

$quote = Invoke-UatApi POST "/cotizaciones" @{
  customerId = $client.id
  customerName = "Cliente Mayorista"
  customerPhone = "8095553333"
  items = @(@{ productId = $productA2.id; qty = 4; unitPrice = 150 })
} $tokenA
if ($quote.priceListId -ne $list.id) {
  throw "Quote price list snapshot missing."
}
if (-not ($quote.items | Where-Object { $_.appliedPriceListId -eq $list.id -and [decimal]$_.unitPrice -eq 150 })) {
  throw "Quote item snapshot missing."
}

$seller = Invoke-UatApi POST "/users" @{
  email = "mayoreo-seller-$run@example.test"
  password = "MayoreoE2E123!"
  nombreCompleto = "Vendedor sin permiso"
  telefono = "8095554444"
  numeroFlota = "$run"
  edad = 30
  role = "VENDEDOR"
  userPermissions = @{
    viewSales = $true
    viewQuotes = $true
    viewClients = $true
    selectManualPriceList = $false
    managePriceLists = $false
  }
} $tokenA
$sellerLogin = Invoke-UatApi POST "/auth/login" @{
  email = $seller.email
  password = "MayoreoE2E123!"
}
$sellerCash = Invoke-UatApi POST "/cash/sessions/open" @{
  openingAmount = 0
  deviceFingerprint = "uat-seller-$run"
} $sellerLogin.accessToken
Invoke-UatApi POST "/sales" @{
  paymentMethod = "cash"
  paymentCashAmount = 80
  cashReceived = 80
  expectedTotalSold = 80
  originCashSessionId = $sellerCash.shiftId
  deviceFingerprint = "uat-seller-$run"
  priceListId = $list.id
  priceListManualOverride = $true
  items = @(@{ productId = $productA1.id; qty = 1; priceSoldUnit = 80 })
} $sellerLogin.accessToken -ExpectedError 403 | Out-Null

foreach ($quantity in @(1, 4, 5, 6)) {
  $boundary = Invoke-UatApi POST '/price-lists/resolve-line' @{
    productId = $productA1.id; qty = $quantity; clientId = $client.id
  } $tokenA
  $expected = if ($quantity -ge 5) { 70 } else { 80 }
  if ([decimal]$boundary.unitPrice -ne $expected) { throw "Quantity boundary failed: $quantity" }
}

$general = Invoke-UatApi POST '/price-lists/resolve-line' @{
  productId = $productA1.id; qty = 5
} $tokenA
if ($general.applied -ne $false -or [decimal]$general.unitPrice -ne 100) {
  throw 'General price without customer/list failed.'
}

$manualList = Invoke-UatApi POST '/price-lists' @{ name = "Distribuidor UAT $run" } $tokenA
Invoke-UatApi POST "/price-lists/$($manualList.id)/rules" @{
  productId = $productA1.id; mode = 'PERCENT_DISCOUNT'; discountPercent = 15; minQuantity = 1
} $tokenA | Out-Null
$manualResolution = Invoke-UatApi POST '/price-lists/resolve-line' @{
  productId = $productA1.id; qty = 5; clientId = $client.id; priceListId = $manualList.id
} $tokenA
if ([decimal]$manualResolution.unitPrice -ne 85) { throw 'Manual list must override customer list.' }
$manualSale = Invoke-UatApi POST '/sales' @{
  customerId = $client.id; priceListId = $manualList.id; priceListManualOverride = $true
  paymentMethod = 'cash'; paymentCashAmount = 425; cashReceived = 425; expectedTotalSold = 425
  originCashSessionId = $cash.shiftId; deviceFingerprint = "uat-$run"
  items = @(@{ productId = $productA1.id; qty = 5; priceSoldUnit = 85 })
} $tokenA
if ($manualSale.priceListId -ne $manualList.id -or [decimal]$manualSale.totalSold -ne 425) {
  throw 'Manual list sale persistence failed.'
}

Invoke-UatApi POST "/price-lists/$($list.id)/rules" @{
  productId = $productA1.id; mode = 'FIXED_PRICE'; fixedPrice = 75; minQuantity = 1
  tiers = @(@{ minQuantity = 5; mode = 'FIXED_PRICE'; fixedPrice = 65 })
} $tokenA | Out-Null
Invoke-UatApi POST "/price-lists/$($list.id)/rules" @{
  productId = $productA2.id; mode = 'PERCENT_DISCOUNT'; discountPercent = 20; minQuantity = 1
  tiers = @(@{ minQuantity = 3; mode = 'PERCENT_DISCOUNT'; discountPercent = 35 })
} $tokenA | Out-Null
$historicalSale = @(Invoke-UatApi GET "/sales?customerId=$($client.id)" $null $tokenA) |
  Where-Object { $_.id -eq $sale.id } | Select-Object -First 1
if (-not $historicalSale) { throw 'Historical sale was not returned by the customer sales query.' }
$historicalQuote = Invoke-UatApi GET "/cotizaciones/$($quote.id)" $null $tokenA
if ([decimal]$historicalSale.items[0].priceSoldUnit -ne 70 -or
    [decimal]$historicalQuote.items[0].unitPrice -ne 150) {
  throw 'Changing rules modified historical prices.'
}

Invoke-UatApi PATCH '/settings' @{ wholesalePriceListsEnabled = $false } $tokenA | Out-Null
$disabledWithRules = Invoke-UatApi POST '/price-lists/resolve-line' @{
  productId = $productA1.id; qty = 5; clientId = $client.id
} $tokenA
if ($disabledWithRules.applied -ne $false -or [decimal]$disabledWithRules.unitPrice -ne 100) {
  throw 'Disabled company must retain general price even with configured rules.'
}

[pscustomobject]@{
  run = $run
  companyA = $companyA.activeCompany.id
  companyB = $companyB.activeCompany.id
  list = $list.id
  fixedUnit = $fixed.unitPrice
  tierUnit = $fixedTier.unitPrice
  discountUnit = $discountTier.unitPrice
  sale = $sale.id
  quote = $quote.id
  status = "PASS"
  quantityBoundaries = 'PASS'
  manualOverridePersistence = 'PASS'
  historicalSnapshots = 'PASS'
  disabledWithExistingRules = 'PASS'
} | ConvertTo-Json -Depth 5
