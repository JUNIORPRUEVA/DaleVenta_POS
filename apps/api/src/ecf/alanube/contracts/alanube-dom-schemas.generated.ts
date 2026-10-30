// Generated from verified public DOM OpenAPI snapshots; do not hand-edit.
export const ALANUBE_DOM_SCHEMAS: Record<string, { source: string; sourceSha256: string; consultedOn: string; country: string; openapi: string; version: string; endpoint: string; schemaSha256: string; request: Record<string, unknown>; responses: Record<string, Record<string, unknown>> }> = {
  "E31": {
    "source": "https://developer.alanube.co/reference/createinvoicefiscals",
    "sourceSha256": "8E665554B8EFC8F41189449E64327F5888F44B05625E48B90BD09F6B8EAE3459",
    "consultedOn": "2026-10-14",
    "country": "DOM",
    "openapi": "3.0.3",
    "version": "1.0.0",
    "endpoint": "/fiscal-invoices",
    "schemaSha256": "6aebf0b7109f3e6d866de44eb171605e2f5e7600e45e13ba3c02b264a08639ba",
    "request": {
      "type": "object",
      "required": [
        "idDoc",
        "sender",
        "buyer",
        "totals",
        "itemDetails"
      ],
      "properties": {
        "company": {
          "type": "object",
          "properties": {
            "id": {
              "type": "string",
              "format": "ulid"
            }
          }
        },
        "idDoc": {
          "type": "object",
          "required": [
            "encf",
            "sequenceDueDate",
            "incomeType",
            "paymentType"
          ],
          "properties": {
            "encf": {
              "type": "string",
              "minLength": 13,
              "maxLength": 13
            },
            "sequenceDueDate": {
              "type": "string",
              "format": "date"
            },
            "deferredDeliveryIndicator": {
              "type": "integer",
              "maxLength": 1
            },
            "taxAmountIndicator": {
              "type": "integer",
              "enum": [
                0,
                1
              ]
            },
            "incomeType": {
              "type": "integer",
              "maxLength": 2,
              "enum": [
                1,
                2,
                3,
                4,
                5,
                6
              ]
            },
            "paymentType": {
              "type": "integer",
              "enum": [
                1,
                2
              ],
              "maxLength": 2
            },
            "paymentDeadline": {
              "type": "string",
              "format": "date"
            },
            "paymentTerm": {
              "type": "string",
              "maxLength": 15
            },
            "paymentFormsTable": {
              "type": "array",
              "maxItems": 7,
              "items": {
                "type": "object",
                "properties": {
                  "paymentMethod": {
                    "type": "integer",
                    "enum": [
                      1,
                      2,
                      3,
                      4,
                      6,
                      7,
                      8
                    ],
                    "maxLength": 2
                  },
                  "paymentAmount": {
                    "type": "number",
                    "minimum": 0,
                    "maximum": 10000000000000000,
                    "multipleOf": 0.01,
                    "maxLength": 19
                  }
                },
                "required": [
                  "paymentMethod",
                  "paymentAmount"
                ]
              }
            },
            "paymentAccountType": {
              "type": "string",
              "maxLength": 2,
              "enum": [
                "CT",
                "AH",
                "OT"
              ]
            },
            "paymentAccountNumber": {
              "type": "string",
              "maxLength": 28
            },
            "bankPayment": {
              "type": "string",
              "maxLength": 75
            },
            "dateFrom": {
              "type": "string",
              "format": "date"
            },
            "dateUntil": {
              "type": "string",
              "format": "date"
            },
            "totalPages": {
              "type": "integer",
              "pattern": "[1-999]",
              "maxLength": 3
            }
          }
        },
        "sender": {
          "type": "object",
          "required": [
            "rnc",
            "companyName",
            "address",
            "stampDate"
          ],
          "properties": {
            "rnc": {
              "type": "string",
              "maxLength": 11
            },
            "companyName": {
              "type": "string",
              "maxLength": 150
            },
            "tradename": {
              "type": "string",
              "maxLength": 150
            },
            "branchOffice": {
              "type": "string",
              "maxLength": 20
            },
            "address": {
              "type": "string",
              "maxLength": 100
            },
            "municipality": {
              "type": "string",
              "pattern": "^[0-9]{6}$"
            },
            "province": {
              "type": "string",
              "pattern": "^[0-9]{6}$"
            },
            "phoneNumber": {
              "type": "array",
              "maxItems": 3,
              "items": {
                "type": "string",
                "maxLength": 12,
                "pattern": "\\d{3}-\\d{3}-\\d{4}"
              }
            },
            "mail": {
              "type": "string",
              "format": "email",
              "maxLength": 80
            },
            "webSite": {
              "type": "string",
              "format": "hostname",
              "maxLength": 50
            },
            "economicActivity": {
              "type": "string",
              "maxLength": 100
            },
            "sellerCode": {
              "type": "string",
              "maxLength": 60
            },
            "internalInvoiceNumber": {
              "type": "string",
              "maxLength": 20
            },
            "internalOrderNumber": {
              "type": "string",
              "maxLength": 20
            },
            "saleArea": {
              "type": "string",
              "maxLength": 20
            },
            "saleRoute": {
              "type": "string",
              "maxLength": 20
            },
            "additionalInformationIssuer": {
              "type": "string",
              "maxLength": 250
            },
            "stampDate": {
              "type": "string",
              "format": "date"
            }
          }
        },
        "buyer": {
          "type": "object",
          "required": [
            "rnc",
            "companyName"
          ],
          "properties": {
            "rnc": {
              "type": "string",
              "maxLength": 11
            },
            "companyName": {
              "type": "string",
              "maxLength": 150
            },
            "contact": {
              "type": "string",
              "maxLength": 80
            },
            "mail": {
              "type": "string",
              "maxLength": 80,
              "format": "email"
            },
            "address": {
              "type": "string",
              "maxLength": 100
            },
            "municipality": {
              "type": "string",
              "pattern": "^[0-9]{6}$"
            },
            "province": {
              "type": "string",
              "pattern": "^[0-9]{6}$"
            },
            "deliverDate": {
              "type": "string",
              "format": "date"
            },
            "contactDelivery": {
              "type": "string",
              "maxLength": 100
            },
            "deliveryAddress": {
              "type": "string",
              "maxLength": 100
            },
            "additionalPhone": {
              "type": "string",
              "maxLength": 12,
              "pattern": "\\d{3}-\\d{3}-\\d{4}"
            },
            "purchaseOrderDate": {
              "type": "string",
              "format": "date"
            },
            "purchaseOrderNumber": {
              "type": "string",
              "maxLength": 20
            },
            "internalCode": {
              "type": "string",
              "maxLength": 20
            },
            "responsibleForPayment": {
              "type": "string",
              "maxLength": 20
            },
            "additionalInformation": {
              "type": "string",
              "maxLength": 150
            }
          }
        },
        "additionalInformation": {
          "type": "object",
          "properties": {
            "shippingDate": {
              "type": "string",
              "format": "date"
            },
            "shipmentNumber": {
              "type": "string",
              "maxLength": 25
            },
            "containerNumber": {
              "type": "string",
              "maxLength": 100
            },
            "referenceNumber": {
              "type": "integer",
              "maxLength": 20
            },
            "grossWeight": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "netWeight": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "grossWeightUnit": {
              "type": "integer",
              "maxLength": 2
            },
            "unitNetWeight": {
              "type": "integer",
              "maxLength": 2
            },
            "bulkQuantity": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "bulkUnit": {
              "type": "integer",
              "maxLength": 2
            },
            "bulkVolume": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "unitVolume": {
              "type": "integer",
              "maxLength": 2
            }
          }
        },
        "transport": {
          "type": "object",
          "properties": {
            "driver": {
              "type": "string",
              "maxLength": 20
            },
            "transportDocument": {
              "type": "integer",
              "maxLength": 20
            },
            "file": {
              "type": "string",
              "maxLength": 20
            },
            "licensePlate": {
              "type": "string",
              "maxLength": 7
            },
            "transportationRoute": {
              "type": "string",
              "maxLength": 20
            },
            "transportationZone": {
              "type": "string",
              "maxLength": 20
            },
            "albaranNumber": {
              "type": "string",
              "maxLength": 20
            }
          }
        },
        "totals": {
          "type": "object",
          "required": [
            "totalAmount"
          ],
          "properties": {
            "totalTaxedAmount": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "i1AmountTaxed": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "i2AmountTaxed": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "i3AmountTaxed": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "exemptAmount": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbisS1": {
              "type": "integer",
              "maxLength": 2,
              "minimum": 0
            },
            "itbisS2": {
              "type": "integer",
              "maxLength": 2,
              "minimum": 0
            },
            "itbisS3": {
              "type": "integer",
              "maxLength": 2,
              "minimum": 0
            },
            "itbisTotal": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbis1Total": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbis2Total": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbis3Total": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "additionalTaxAmount": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "additionalTaxes": {
              "type": "array",
              "maxItems": 20,
              "items": {
                "type": "object",
                "required": [
                  "taxType"
                ],
                "properties": {
                  "taxType": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 39
                  },
                  "additionalTaxRate": {
                    "type": "number",
                    "multipleOf": 0.01,
                    "minimum": 0,
                    "maximum": 999.99
                  },
                  "selectiveTaxAmountSpecificConsumption": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  },
                  "amountSelectiveConsumptionTaxAdvalorem": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  },
                  "otherAdditionalTaxes": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  }
                }
              }
            },
            "totalAmount": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "nonBillableAmount": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "amountPeriod": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "previousBalance": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "amountAdvancePayment": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "payValue": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbisTotalRetained": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "isrTotalRetention": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbisTotalPerception": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "isrTotalPerception": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            }
          }
        },
        "otherCurrency": {
          "type": "object",
          "required": [
            "currencyType",
            "exchangeRate",
            "totalAmountOtherCurrency"
          ],
          "properties": {
            "currencyType": {
              "type": "string",
              "enum": [
                "BRL",
                "CAD",
                "CHF",
                "CHY",
                "XDR",
                "DKK",
                "EUR",
                "GBP",
                "JPY",
                "NOK",
                "SCP",
                "SEK",
                "USD",
                "VEF"
              ]
            },
            "exchangeRate": {
              "type": "number",
              "maxLength": 7,
              "minimum": 0,
              "multipleOf": 0.0001
            },
            "totalTaxedAmountOtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "amountTaxed1OtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "amountTaxed2OtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "amountTaxed3OtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "exemptAmountOtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbisTotalOtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbis1TotalOtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbis2TotalOtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbis3TotalOtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "additionalTaxAmountOtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "additionalTaxesOtherCurrency": {
              "type": "array",
              "maxItems": 20,
              "items": {
                "type": "object",
                "required": [
                  "taxTypeOtherCurrency"
                ],
                "properties": {
                  "taxTypeOtherCurrency": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 39
                  },
                  "additionalTaxRateOtherCurrency": {
                    "type": "number",
                    "multipleOf": 0.01,
                    "minimum": 0,
                    "maximum": 999.99
                  },
                  "selectiveTaxAmountSpecificConsumptionOtherCurrency": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  },
                  "amountSelectiveConsumptionTaxAdvaloremOtherCurrency": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  },
                  "otherAdditionalTaxesOtherCurrency": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  }
                }
              }
            },
            "totalAmountOtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            }
          }
        },
        "itemDetails": {
          "type": "array",
          "minItems": 1,
          "maxItems": 1000,
          "items": {
            "type": "object",
            "required": [
              "lineNumber",
              "billingIndicator",
              "itemName",
              "goodServiceIndicator",
              "quantityItem",
              "unitPriceItem",
              "itemAmount"
            ],
            "properties": {
              "lineNumber": {
                "type": "integer"
              },
              "itemCodeTable": {
                "type": "array",
                "maxItems": 5,
                "items": {
                  "type": "object",
                  "properties": {
                    "codeType": {
                      "type": "string",
                      "maxLength": 14
                    },
                    "itemCode": {
                      "type": "string"
                    }
                  }
                }
              },
              "billingIndicator": {
                "type": "integer",
                "maxLength": 1,
                "enum": [
                  0,
                  1,
                  2,
                  3,
                  4
                ]
              },
              "retention": {
                "type": "object",
                "properties": {
                  "indicatorAgentWithholdingPerception": {
                    "type": "integer",
                    "enum": [
                      1,
                      2
                    ]
                  },
                  "itbisAmountWithheld": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  },
                  "isrAmountWithheld": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  }
                }
              },
              "itemName": {
                "type": "string",
                "maxLength": 80
              },
              "goodServiceIndicator": {
                "type": "integer",
                "enum": [
                  1,
                  2
                ]
              },
              "itemDescription": {
                "type": "string",
                "maxLength": 1000
              },
              "quantityItem": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "unitMeasure": {
                "type": "integer",
                "minimum": 1,
                "maximum": 62
              },
              "quantityReference": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "referenceUnit": {
                "type": "integer",
                "maxLength": 2
              },
              "subquantityTable": {
                "type": "array",
                "maxItems": 5,
                "items": {
                  "type": "object",
                  "properties": {
                    "subquantity": {
                      "type": "number",
                      "minimum": 0,
                      "multipleOf": 0.001,
                      "maxLength": 19
                    },
                    "codeSubquantity": {
                      "type": "integer",
                      "minimum": 0,
                      "maxLength": 2
                    }
                  }
                }
              },
              "degreesAlcohol": {
                "type": "number",
                "maxLength": 6,
                "maximum": 99,
                "minimum": 0,
                "multipleOf": 0.001
              },
              "unitPriceReference": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "elaborationDate": {
                "type": "string",
                "format": "date"
              },
              "expirationDateItem": {
                "type": "string",
                "format": "date"
              },
              "unitPriceItem": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.0001,
                "maxLength": 21,
                "maximum": 1000000000000000000
              },
              "discountAmount": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subDiscounts": {
                "type": "array",
                "maxItems": 12,
                "items": {
                  "type": "object",
                  "properties": {
                    "subDiscountRate": {
                      "type": "string",
                      "enum": [
                        "$",
                        "%"
                      ]
                    },
                    "subDiscountPercentage": {
                      "type": "number",
                      "maxLength": 5,
                      "minimum": 0,
                      "multipleOf": 0.01
                    },
                    "subDiscountAmount": {
                      "type": "number",
                      "minimum": 0,
                      "multipleOf": 0.01,
                      "maxLength": 19,
                      "maximum": 10000000000000000
                    }
                  }
                }
              },
              "surchargeAmount": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subSurcharge": {
                "type": "array",
                "maxItems": 12,
                "items": {
                  "type": "object",
                  "properties": {
                    "subSurchargeType": {
                      "type": "string",
                      "enum": [
                        "$",
                        "%"
                      ]
                    },
                    "subSurchargePercentage": {
                      "type": "number",
                      "maxLength": 5,
                      "minimum": 0,
                      "multipleOf": 0.01
                    },
                    "subSurchargeAmount": {
                      "type": "number",
                      "minimum": 0,
                      "multipleOf": 0.01,
                      "maxLength": 19,
                      "maximum": 10000000000000000
                    }
                  }
                }
              },
              "additionalTaxes": {
                "type": "array",
                "maxItems": 2,
                "items": {
                  "type": "object",
                  "required": [
                    "taxType"
                  ],
                  "properties": {
                    "taxType": {
                      "type": "integer",
                      "minimum": 1,
                      "maximum": 39
                    }
                  }
                }
              },
              "otherCurrencyDetail": {
                "type": "object",
                "required": [
                  "priceOtherCurrency",
                  "amountItemOtherCurrency"
                ],
                "properties": {
                  "priceOtherCurrency": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.0001,
                    "maxLength": 21,
                    "maximum": 1000000000000000000
                  },
                  "discountOtherCurrency": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  },
                  "surchargeAnotherCurrency": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  },
                  "amountItemOtherCurrency": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  }
                }
              },
              "itemAmount": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              }
            }
          }
        },
        "subtotals": {
          "type": "array",
          "maxItems": 20,
          "items": {
            "type": "object",
            "properties": {
              "subTotalNumber": {
                "type": "integer",
                "maxLength": 2
              },
              "subtotalDescription": {
                "type": "string",
                "maxLength": 40
              },
              "order": {
                "type": "integer",
                "maxLength": 2
              },
              "subTotalAmountTaxedTotal": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subTotalAmountTaxedI1": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subTotalAmountTaxedI2": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subTotalAmountTaxedI3": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "itbisSubTotal": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "itbis1SubTotal": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "itbis2SubTotal": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "itbis3SubTotal": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subTotalAdditionalTax": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subTotalExempt": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subTotalAmount": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "lines": {
                "type": "integer",
                "maxLength": 2
              }
            }
          }
        },
        "discountsOrSurcharges": {
          "type": "array",
          "maxItems": 20,
          "items": {
            "type": "object",
            "properties": {
              "lineNumber": {
                "type": "integer",
                "maxLength": 2
              },
              "fitType": {
                "type": "string",
                "maxLength": 1,
                "enum": [
                  "D",
                  "R"
                ]
              },
              "norma1007Indicator": {
                "type": "integer",
                "maxLength": 1
              },
              "descriptionDiscountOrSurcharge": {
                "type": "string",
                "maxLength": 45
              },
              "typeValue": {
                "type": "string",
                "maxLength": 1,
                "enum": [
                  "%",
                  "$"
                ]
              },
              "discountValueOrSurcharge": {
                "type": "number",
                "maxLength": 6,
                "maximum": 999,
                "minimum": 0,
                "multipleOf": 0.01
              },
              "discountAmountOrSurcharge": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "discountAmountOrSurchargeOtherCurrency": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "indicatorBillingDiscountOrSurcharge": {
                "type": "integer",
                "maxLength": 1
              }
            }
          }
        },
        "pagination": {
          "type": "array",
          "minItems": 2,
          "maxItems": 100,
          "items": {
            "type": "object",
            "properties": {
              "pageNo": {
                "type": "integer",
                "maxLength": 3,
                "minimum": 0
              },
              "noLineFrom": {
                "type": "integer",
                "maxLength": 3,
                "minimum": 0
              },
              "noLineUntil": {
                "type": "integer",
                "maxLength": 3,
                "minimum": 0
              },
              "subtotalAmountTaxedPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subtotalAmountTaxed1Page": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subtotalAmountTaxed2Page": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subtotalAmountTaxed3Page": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "exemptSubtotalPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "itbisSubtotalPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "itbis1SubtotalPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "itbis2SubtotalPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "itbis3SubtotalPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subtotalAdditionalTaxPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subtotalAdditionalTax": {
                "type": "object",
                "properties": {
                  "subtotalSelectiveTaxForSpecificConsumptionPage": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  },
                  "subtotalOtherTax": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  }
                }
              },
              "subtotalAmountPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subtotalNonBillableAmountPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              }
            }
          }
        },
        "informationReference": {
          "type": "object",
          "properties": {
            "ncfModified": {
              "type": "string",
              "maxLength": 19
            },
            "rncOtherTaxpayer": {
              "type": "string",
              "maxLength": 11
            },
            "ncfModifiedDate": {
              "type": "string",
              "format": "date"
            },
            "modificationCode": {
              "type": "integer",
              "enum": [
                4,
                5
              ]
            }
          }
        },
        "config": {
          "type": "object",
          "properties": {
            "pdf": {
              "type": "object",
              "properties": {
                "type": {
                  "type": "string",
                  "enum": [
                    "generic",
                    "pos"
                  ]
                },
                "note": {
                  "type": "string",
                  "maxLength": 250
                }
              }
            }
          }
        }
      }
    },
    "responses": {
      "201": {
        "type": "object",
        "properties": {
          "id": {
            "type": "string",
            "format": "ulid"
          },
          "stampDate": {
            "type": "string",
            "format": "date"
          },
          "status": {
            "type": "string",
            "enum": [
              "REGISTERED",
              "TO_SEND",
              "WAITING_RESPONSE",
              "TO_NOTIFY",
              "FINISHED"
            ]
          },
          "companyIdentification": {
            "type": "string"
          },
          "encf": {
            "type": "string"
          },
          "pdf": {
            "type": "string",
            "format": "uri"
          },
          "documentStampUrl": {
            "type": "string",
            "format": "uri"
          },
          "signatureDate": {
            "type": "string",
            "format": "date-time"
          },
          "securityCode": {
            "type": "string"
          },
          "sequenceConsumed": {
            "type": "boolean"
          }
        }
      },
      "400": {
        "type": "object",
        "properties": {
          "code": {
            "type": "string"
          },
          "message": {
            "type": "string"
          }
        }
      },
      "404": {
        "type": "object",
        "properties": {
          "code": {
            "type": "string"
          },
          "message": {
            "type": "string"
          }
        }
      },
      "500": {
        "type": "object",
        "properties": {
          "code": {
            "type": "string"
          },
          "message": {
            "type": "string"
          }
        }
      }
    }
  },
  "E32": {
    "source": "https://developer.alanube.co/reference/createinvoices",
    "sourceSha256": "483A7220F503AF4FAEEE1D42CF2124449CF8524105F94172D633099CEAF836DF",
    "consultedOn": "2026-10-14",
    "country": "DOM",
    "openapi": "3.0.3",
    "version": "1.0.0",
    "endpoint": "/invoices",
    "schemaSha256": "b3436ce66bb57ab45c957a9e28cbc68c3595bf1a85605654d7b0d0608bf4bac6",
    "request": {
      "type": "object",
      "required": [
        "idDoc",
        "sender",
        "totals",
        "itemDetails"
      ],
      "properties": {
        "company": {
          "type": "object",
          "properties": {
            "id": {
              "type": "string",
              "format": "ulid"
            }
          },
          "required": [
            "id"
          ]
        },
        "idDoc": {
          "type": "object",
          "required": [
            "encf",
            "paymentType",
            "incomeType"
          ],
          "properties": {
            "encf": {
              "type": "string",
              "minLength": 13,
              "maxLength": 13
            },
            "deferredDeliveryIndicator": {
              "type": "integer",
              "maxLength": 1
            },
            "taxAmountIndicator": {
              "type": "integer",
              "enum": [
                0,
                1
              ]
            },
            "incomeType": {
              "type": "integer",
              "maxLength": 2,
              "enum": [
                1,
                2,
                3,
                4,
                5,
                6
              ]
            },
            "paymentType": {
              "type": "integer",
              "enum": [
                1,
                2,
                3
              ],
              "maxLength": 2
            },
            "paymentDeadline": {
              "type": "string",
              "format": "date"
            },
            "paymentTerm": {
              "type": "string",
              "maxLength": 15
            },
            "paymentFormsTable": {
              "type": "array",
              "maxItems": 7,
              "items": {
                "type": "object",
                "properties": {
                  "paymentMethod": {
                    "type": "integer",
                    "enum": [
                      1,
                      2,
                      3,
                      4,
                      5,
                      6,
                      7,
                      8
                    ],
                    "maxLength": 2
                  },
                  "paymentAmount": {
                    "type": "number",
                    "minimum": 0,
                    "maximum": 10000000000000000,
                    "multipleOf": 0.01,
                    "maxLength": 19
                  }
                },
                "required": [
                  "paymentMethod",
                  "paymentAmount"
                ]
              }
            },
            "paymentAccountType": {
              "type": "string",
              "maxLength": 2,
              "enum": [
                "CT",
                "AH",
                "OT"
              ]
            },
            "paymentAccountNumber": {
              "type": "string",
              "maxLength": 28
            },
            "bankPayment": {
              "type": "string",
              "maxLength": 75
            },
            "dateFrom": {
              "type": "string",
              "format": "date"
            },
            "dateUntil": {
              "type": "string",
              "format": "date"
            },
            "totalPages": {
              "type": "integer",
              "pattern": "[1-999]",
              "maxLength": 3
            }
          }
        },
        "sender": {
          "type": "object",
          "required": [
            "rnc",
            "companyName",
            "address",
            "stampDate"
          ],
          "properties": {
            "rnc": {
              "type": "string",
              "maxLength": 11
            },
            "companyName": {
              "type": "string",
              "maxLength": 150
            },
            "tradename": {
              "type": "string",
              "maxLength": 150
            },
            "branchOffice": {
              "type": "string",
              "maxLength": 20
            },
            "address": {
              "type": "string",
              "maxLength": 100
            },
            "municipality": {
              "type": "string",
              "pattern": "^[0-9]{6}$"
            },
            "province": {
              "type": "string",
              "pattern": "^[0-9]{6}$"
            },
            "phoneNumber": {
              "type": "array",
              "maxItems": 3,
              "items": {
                "type": "string",
                "maxLength": 12,
                "pattern": "\\d{3}-\\d{3}-\\d{4}"
              }
            },
            "mail": {
              "type": "string",
              "format": "email",
              "maxLength": 80
            },
            "webSite": {
              "type": "string",
              "format": "hostname",
              "maxLength": 50
            },
            "economicActivity": {
              "type": "string",
              "maxLength": 100
            },
            "sellerCode": {
              "type": "string",
              "maxLength": 60
            },
            "internalInvoiceNumber": {
              "type": "string",
              "maxLength": 20
            },
            "internalOrderNumber": {
              "type": "string",
              "maxLength": 20
            },
            "saleArea": {
              "type": "string",
              "maxLength": 20
            },
            "saleRoute": {
              "type": "string",
              "maxLength": 20
            },
            "additionalInformationIssuer": {
              "type": "string",
              "maxLength": 250
            },
            "stampDate": {
              "type": "string",
              "format": "date"
            }
          }
        },
        "buyer": {
          "type": "object",
          "properties": {
            "rnc": {
              "type": "string",
              "maxLength": 11
            },
            "foreignIdentifier": {
              "type": "string",
              "maxLength": 20
            },
            "companyName": {
              "type": "string",
              "maxLength": 150
            },
            "contact": {
              "type": "string",
              "maxLength": 80
            },
            "mail": {
              "type": "string",
              "maxLength": 80,
              "format": "email"
            },
            "address": {
              "type": "string",
              "maxLength": 100
            },
            "municipality": {
              "type": "string",
              "pattern": "^[0-9]{6}$"
            },
            "province": {
              "type": "string",
              "pattern": "^[0-9]{6}$"
            },
            "deliverDate": {
              "type": "string",
              "format": "date"
            },
            "contactDelivery": {
              "type": "string",
              "maxLength": 100
            },
            "deliveryAddress": {
              "type": "string",
              "maxLength": 100
            },
            "additionalPhone": {
              "type": "string",
              "maxLength": 12,
              "pattern": "\\d{3}-\\d{3}-\\d{4}"
            },
            "purchaseOrderDate": {
              "type": "string",
              "format": "date"
            },
            "purchaseOrderNumber": {
              "type": "string",
              "maxLength": 20
            },
            "internalCode": {
              "type": "string",
              "maxLength": 20
            },
            "responsibleForPayment": {
              "type": "string",
              "maxLength": 20
            },
            "additionalInformation": {
              "type": "string",
              "maxLength": 150
            }
          }
        },
        "additionalInformation": {
          "type": "object",
          "properties": {
            "shippingDate": {
              "type": "string",
              "format": "date"
            },
            "shipmentNumber": {
              "type": "string",
              "maxLength": 25
            },
            "containerNumber": {
              "type": "string",
              "maxLength": 100
            },
            "referenceNumber": {
              "type": "integer",
              "maxLength": 20
            },
            "grossWeight": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "netWeight": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "grossWeightUnit": {
              "type": "integer",
              "maxLength": 2
            },
            "unitNetWeight": {
              "type": "integer",
              "maxLength": 2
            },
            "bulkQuantity": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "bulkUnit": {
              "type": "integer",
              "maxLength": 2
            },
            "bulkVolume": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "unitVolume": {
              "type": "integer",
              "maxLength": 2
            }
          }
        },
        "transport": {
          "type": "object",
          "properties": {
            "driver": {
              "type": "string",
              "maxLength": 20
            },
            "transportDocument": {
              "type": "integer",
              "maxLength": 20
            },
            "file": {
              "type": "string",
              "maxLength": 20
            },
            "licensePlate": {
              "type": "string",
              "maxLength": 7
            },
            "transportationRoute": {
              "type": "string",
              "maxLength": 20
            },
            "transportationZone": {
              "type": "string",
              "maxLength": 20
            },
            "albaranNumber": {
              "type": "string",
              "maxLength": 20
            }
          }
        },
        "totals": {
          "type": "object",
          "required": [
            "totalAmount"
          ],
          "properties": {
            "totalTaxedAmount": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "i1AmountTaxed": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "i2AmountTaxed": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "i3AmountTaxed": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "exemptAmount": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbisS1": {
              "type": "integer",
              "maxLength": 2,
              "minimum": 0
            },
            "itbisS2": {
              "type": "integer",
              "maxLength": 2,
              "minimum": 0
            },
            "itbisS3": {
              "type": "integer",
              "maxLength": 2,
              "minimum": 0
            },
            "itbisTotal": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbis1Total": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbis2Total": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbis3Total": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "additionalTaxAmount": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "additionalTaxes": {
              "type": "array",
              "maxItems": 20,
              "items": {
                "type": "object",
                "required": [
                  "taxType"
                ],
                "properties": {
                  "taxType": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 39
                  },
                  "additionalTaxRate": {
                    "type": "number",
                    "multipleOf": 0.01,
                    "minimum": 0,
                    "maximum": 999.99
                  },
                  "selectiveTaxAmountSpecificConsumption": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  },
                  "amountSelectiveConsumptionTaxAdvalorem": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  },
                  "otherAdditionalTaxes": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  }
                }
              }
            },
            "totalAmount": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "nonBillableAmount": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "amountPeriod": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "previousBalance": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "amountAdvancePayment": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "payValue": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            }
          }
        },
        "otherCurrency": {
          "type": "object",
          "required": [
            "currencyType",
            "exchangeRate",
            "totalAmountOtherCurrency"
          ],
          "properties": {
            "currencyType": {
              "type": "string",
              "enum": [
                "BRL",
                "CAD",
                "CHF",
                "CHY",
                "XDR",
                "DKK",
                "EUR",
                "GBP",
                "JPY",
                "NOK",
                "SCP",
                "SEK",
                "USD",
                "VEF"
              ]
            },
            "exchangeRate": {
              "type": "number",
              "maxLength": 7,
              "minimum": 0,
              "multipleOf": 0.0001
            },
            "totalTaxedAmountOtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "amountTaxed1OtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "amountTaxed2OtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "amountTaxed3OtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "exemptAmountOtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbisTotalOtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbis1TotalOtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbis2TotalOtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbis3TotalOtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "additionalTaxAmountOtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "additionalTaxesOtherCurrency": {
              "type": "array",
              "maxItems": 20,
              "items": {
                "type": "object",
                "required": [
                  "taxTypeOtherCurrency"
                ],
                "properties": {
                  "taxTypeOtherCurrency": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 39
                  },
                  "additionalTaxRateOtherCurrency": {
                    "type": "number",
                    "multipleOf": 0.01,
                    "minimum": 0,
                    "maximum": 999.99
                  },
                  "selectiveTaxAmountSpecificConsumptionOtherCurrency": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  },
                  "amountSelectiveConsumptionTaxAdvaloremOtherCurrency": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  },
                  "otherAdditionalTaxesOtherCurrency": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  }
                }
              }
            },
            "totalAmountOtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            }
          }
        },
        "itemDetails": {
          "type": "array",
          "minItems": 1,
          "items": {
            "type": "object",
            "required": [
              "lineNumber",
              "billingIndicator",
              "itemName",
              "goodServiceIndicator",
              "quantityItem",
              "unitPriceItem",
              "itemAmount"
            ],
            "properties": {
              "lineNumber": {
                "type": "integer"
              },
              "itemCodeTable": {
                "type": "array",
                "maxItems": 5,
                "items": {
                  "type": "object",
                  "properties": {
                    "codeType": {
                      "type": "string",
                      "maxLength": 14
                    },
                    "itemCode": {
                      "type": "string"
                    }
                  }
                }
              },
              "billingIndicator": {
                "type": "integer",
                "maxLength": 1,
                "enum": [
                  0,
                  1,
                  2,
                  3,
                  4
                ]
              },
              "itemName": {
                "type": "string",
                "maxLength": 80
              },
              "goodServiceIndicator": {
                "type": "integer",
                "enum": [
                  1,
                  2
                ]
              },
              "itemDescription": {
                "type": "string",
                "maxLength": 1000
              },
              "quantityItem": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "unitMeasure": {
                "type": "integer",
                "minimum": 1,
                "maximum": 62
              },
              "quantityReference": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "referenceUnit": {
                "type": "integer",
                "maxLength": 2
              },
              "subquantityTable": {
                "type": "array",
                "maxItems": 5,
                "items": {
                  "type": "object",
                  "properties": {
                    "subquantity": {
                      "type": "number",
                      "minimum": 0,
                      "multipleOf": 0.001,
                      "maxLength": 19
                    },
                    "codeSubquantity": {
                      "type": "integer",
                      "minimum": 0,
                      "maxLength": 2
                    }
                  }
                }
              },
              "degreesAlcohol": {
                "type": "number",
                "maxLength": 6,
                "maximum": 99,
                "minimum": 0,
                "multipleOf": 0.001
              },
              "unitPriceReference": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "elaborationDate": {
                "type": "string",
                "format": "date"
              },
              "expirationDateItem": {
                "type": "string",
                "format": "date"
              },
              "mining": {
                "type": "object",
                "properties": {
                  "netWeightKilogram": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.001,
                    "maxLength": 19
                  },
                  "netWeightMining": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.001,
                    "maxLength": 19
                  },
                  "affiliationType": {
                    "type": "integer",
                    "enum": [
                      1,
                      2
                    ]
                  },
                  "settlement": {
                    "type": "integer",
                    "enum": [
                      1,
                      2
                    ]
                  }
                }
              },
              "unitPriceItem": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.0001,
                "maxLength": 21,
                "maximum": 1000000000000000000
              },
              "discountAmount": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subDiscounts": {
                "type": "array",
                "maxItems": 12,
                "items": {
                  "type": "object",
                  "properties": {
                    "subDiscountRate": {
                      "type": "string",
                      "enum": [
                        "$",
                        "%"
                      ]
                    },
                    "subDiscountPercentage": {
                      "type": "number",
                      "maxLength": 5,
                      "minimum": 0,
                      "multipleOf": 0.01
                    },
                    "subDiscountAmount": {
                      "type": "number",
                      "minimum": 0,
                      "multipleOf": 0.01,
                      "maxLength": 19,
                      "maximum": 10000000000000000
                    }
                  }
                }
              },
              "surchargeAmount": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subSurcharge": {
                "type": "array",
                "maxItems": 12,
                "items": {
                  "type": "object",
                  "properties": {
                    "subSurchargeType": {
                      "type": "string",
                      "enum": [
                        "$",
                        "%"
                      ]
                    },
                    "subSurchargePercentage": {
                      "type": "number",
                      "maxLength": 5,
                      "minimum": 0,
                      "multipleOf": 0.01
                    },
                    "subSurchargeAmount": {
                      "type": "number",
                      "minimum": 0,
                      "multipleOf": 0.01,
                      "maxLength": 19,
                      "maximum": 10000000000000000
                    }
                  }
                }
              },
              "additionalTaxes": {
                "type": "array",
                "maxItems": 2,
                "items": {
                  "type": "object",
                  "required": [
                    "taxType"
                  ],
                  "properties": {
                    "taxType": {
                      "type": "integer",
                      "minimum": 1,
                      "maximum": 39
                    }
                  }
                }
              },
              "otherCurrencyDetail": {
                "type": "object",
                "required": [
                  "priceOtherCurrency",
                  "amountItemOtherCurrency"
                ],
                "properties": {
                  "priceOtherCurrency": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.0001,
                    "maxLength": 21,
                    "maximum": 1000000000000000000
                  },
                  "discountOtherCurrency": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  },
                  "surchargeAnotherCurrency": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  },
                  "amountItemOtherCurrency": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  }
                }
              },
              "itemAmount": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              }
            }
          }
        },
        "subtotals": {
          "type": "array",
          "maxItems": 20,
          "items": {
            "type": "object",
            "properties": {
              "subTotalNumber": {
                "type": "integer",
                "maxLength": 2
              },
              "subtotalDescription": {
                "type": "string",
                "maxLength": 40
              },
              "order": {
                "type": "integer",
                "maxLength": 2
              },
              "subTotalAmountTaxedTotal": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subTotalAmountTaxedI1": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subTotalAmountTaxedI2": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subTotalAmountTaxedI3": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "itbisSubTotal": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "itbis1SubTotal": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "itbis2SubTotal": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "itbis3SubTotal": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subTotalAdditionalTax": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subTotalExempt": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subTotalAmount": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "lines": {
                "type": "integer",
                "maxLength": 2
              }
            }
          }
        },
        "discountsOrSurcharges": {
          "type": "array",
          "maxItems": 20,
          "items": {
            "type": "object",
            "properties": {
              "lineNumber": {
                "type": "integer",
                "maxLength": 2
              },
              "fitType": {
                "type": "string",
                "maxLength": 1,
                "enum": [
                  "D",
                  "R"
                ]
              },
              "norma1007Indicator": {
                "type": "integer",
                "maxLength": 1
              },
              "descriptionDiscountOrSurcharge": {
                "type": "string",
                "maxLength": 45
              },
              "typeValue": {
                "type": "string",
                "maxLength": 1,
                "enum": [
                  "%",
                  "$"
                ]
              },
              "discountValueOrSurcharge": {
                "type": "number",
                "maxLength": 6,
                "maximum": 999,
                "minimum": 0,
                "multipleOf": 0.01
              },
              "discountAmountOrSurcharge": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "discountAmountOrSurchargeOtherCurrency": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "indicatorBillingDiscountOrSurcharge": {
                "type": "integer",
                "maxLength": 1
              }
            }
          }
        },
        "pagination": {
          "type": "array",
          "minItems": 2,
          "maxItems": 100,
          "items": {
            "type": "object",
            "properties": {
              "pageNo": {
                "type": "integer",
                "maxLength": 3,
                "minimum": 0
              },
              "noLineFrom": {
                "type": "integer",
                "maxLength": 3,
                "minimum": 0
              },
              "noLineUntil": {
                "type": "integer",
                "maxLength": 3,
                "minimum": 0
              },
              "subtotalAmountTaxedPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subtotalAmountTaxed1Page": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subtotalAmountTaxed2Page": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subtotalAmountTaxed3Page": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "exemptSubtotalPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "itbisSubtotalPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "itbis1SubtotalPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "itbis2SubtotalPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "itbis3SubtotalPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subtotalAdditionalTaxPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subtotalAdditionalTax": {
                "type": "object",
                "properties": {
                  "subtotalSelectiveTaxForSpecificConsumptionPage": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  },
                  "subtotalOtherTax": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  }
                }
              },
              "subtotalAmountPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subtotalNonBillableAmountPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              }
            }
          }
        },
        "informationReference": {
          "type": "object",
          "properties": {
            "ncfModified": {
              "type": "string",
              "maxLength": 19
            },
            "rncOtherTaxpayer": {
              "type": "string",
              "maxLength": 11
            },
            "ncfModifiedDate": {
              "type": "string",
              "format": "date"
            },
            "modificationCode": {
              "type": "integer",
              "enum": [
                4
              ]
            }
          }
        },
        "config": {
          "type": "object",
          "properties": {
            "pdf": {
              "type": "object",
              "properties": {
                "type": {
                  "type": "string",
                  "enum": [
                    "generic",
                    "pos"
                  ]
                },
                "note": {
                  "type": "string",
                  "maxLength": 250
                }
              }
            }
          }
        }
      }
    },
    "responses": {
      "201": {
        "type": "object",
        "properties": {
          "id": {
            "type": "string",
            "format": "ulid"
          },
          "stampDate": {
            "type": "string",
            "format": "date"
          },
          "status": {
            "type": "string",
            "enum": [
              "REGISTERED",
              "TO_SEND",
              "WAITING_RESPONSE",
              "TO_NOTIFY",
              "FINISHED"
            ]
          },
          "legalStatus": {
            "type": "string",
            "enum": [
              "ACCEPTED",
              "ACCEPTED_WITH_OBSERVATIONS",
              "REJECTED"
            ]
          },
          "companyIdentification": {
            "type": "string"
          },
          "documentNumber": {
            "type": "string"
          },
          "documentStampUrl": {
            "type": "string",
            "format": "uri"
          },
          "resumeXml": {
            "type": "string",
            "format": "uri"
          },
          "pdf": {
            "type": "string",
            "format": "uri"
          },
          "signatureDate": {
            "type": "string",
            "format": "date-time"
          },
          "securityCode": {
            "type": "string"
          },
          "sequenceConsumed": {
            "type": "boolean"
          },
          "governmentResponse": {
            "type": "object",
            "properties": {
              "value": {
                "type": "array",
                "items": {
                  "type": "object",
                  "properties": {
                    "valor": {
                      "type": "string"
                    },
                    "codigo": {
                      "type": "string"
                    }
                  }
                }
              },
              "code": {
                "type": "integer"
              }
            }
          },
          "response": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "code": {
                  "type": "string"
                },
                "message": {
                  "type": "string"
                }
              }
            }
          }
        }
      },
      "400": {
        "type": "object",
        "properties": {
          "code": {
            "type": "string"
          },
          "message": {
            "type": "string"
          }
        }
      },
      "404": {
        "type": "object",
        "properties": {
          "code": {
            "type": "string"
          },
          "message": {
            "type": "string"
          }
        }
      },
      "500": {
        "type": "object",
        "properties": {
          "code": {
            "type": "string"
          },
          "message": {
            "type": "string"
          }
        }
      }
    }
  },
  "E34": {
    "source": "https://developer.alanube.co/reference/createcreditnotes",
    "sourceSha256": "7B118AC204B241B79E5F4EAF7D2445C094933B6A979D83BDBB56AB53B18698E0",
    "consultedOn": "2026-10-14",
    "country": "DOM",
    "openapi": "3.0.3",
    "version": "1.0.0",
    "endpoint": "/credit-notes",
    "schemaSha256": "a54a0c4fb63538d32b9242c87bc8bbc9888f5b44fbe922fd2eb53561765727dd",
    "request": {
      "type": "object",
      "required": [
        "idDoc",
        "sender",
        "totals",
        "itemDetails",
        "informationReference"
      ],
      "properties": {
        "company": {
          "type": "object",
          "properties": {
            "id": {
              "type": "string",
              "format": "ulid"
            }
          }
        },
        "idDoc": {
          "type": "object",
          "required": [
            "encf",
            "creditNoteIndicator",
            "paymentType"
          ],
          "properties": {
            "encf": {
              "type": "string",
              "minLength": 13,
              "maxLength": 13
            },
            "creditNoteIndicator": {
              "type": "integer",
              "enum": [
                1,
                0
              ],
              "maxLength": 1
            },
            "deferredDeliveryIndicator": {
              "type": "integer",
              "maxLength": 1
            },
            "taxAmountIndicator": {
              "type": "integer",
              "enum": [
                0,
                1
              ]
            },
            "incomeType": {
              "type": "integer",
              "maxLength": 2,
              "enum": [
                1,
                2,
                3,
                4,
                5,
                6
              ]
            },
            "paymentType": {
              "type": "integer",
              "enum": [
                1,
                2,
                3
              ],
              "maxLength": 2
            },
            "paymentDeadline": {
              "type": "string",
              "format": "date"
            },
            "dateFrom": {
              "type": "string",
              "format": "date"
            },
            "dateUntil": {
              "type": "string",
              "format": "date"
            },
            "totalPages": {
              "type": "integer",
              "pattern": "[1-999]",
              "maxLength": 3
            }
          }
        },
        "sender": {
          "type": "object",
          "required": [
            "rnc",
            "companyName",
            "address",
            "stampDate"
          ],
          "properties": {
            "rnc": {
              "type": "string",
              "maxLength": 11
            },
            "companyName": {
              "type": "string",
              "maxLength": 150
            },
            "tradename": {
              "type": "string",
              "maxLength": 150
            },
            "branchOffice": {
              "type": "string",
              "maxLength": 20
            },
            "address": {
              "type": "string",
              "maxLength": 100
            },
            "municipality": {
              "type": "string",
              "pattern": "^[0-9]{6}$"
            },
            "province": {
              "type": "string",
              "pattern": "^[0-9]{6}$"
            },
            "phoneNumber": {
              "type": "array",
              "maxItems": 3,
              "items": {
                "type": "string",
                "maxLength": 12,
                "pattern": "\\d{3}-\\d{3}-\\d{4}"
              }
            },
            "mail": {
              "type": "string",
              "format": "email",
              "maxLength": 80
            },
            "webSite": {
              "type": "string",
              "format": "hostname",
              "maxLength": 50
            },
            "economicActivity": {
              "type": "string",
              "maxLength": 100
            },
            "sellerCode": {
              "type": "string",
              "maxLength": 60
            },
            "internalInvoiceNumber": {
              "type": "string",
              "maxLength": 20
            },
            "internalOrderNumber": {
              "type": "string",
              "maxLength": 20
            },
            "saleArea": {
              "type": "string",
              "maxLength": 20
            },
            "saleRoute": {
              "type": "string",
              "maxLength": 20
            },
            "additionalInformationIssuer": {
              "type": "string",
              "maxLength": 250
            },
            "stampDate": {
              "type": "string",
              "format": "date"
            }
          }
        },
        "buyer": {
          "type": "object",
          "properties": {
            "rnc": {
              "type": "string",
              "maxLength": 11
            },
            "foreignIdentifier": {
              "type": "string",
              "maxLength": 20
            },
            "companyName": {
              "type": "string",
              "maxLength": 150
            },
            "contact": {
              "type": "string",
              "maxLength": 80
            },
            "mail": {
              "type": "string",
              "maxLength": 80,
              "format": "email"
            },
            "address": {
              "type": "string",
              "maxLength": 100
            },
            "municipality": {
              "type": "string",
              "pattern": "^[0-9]{6}$"
            },
            "province": {
              "type": "string",
              "pattern": "^[0-9]{6}$"
            },
            "deliverDate": {
              "type": "string",
              "format": "date"
            },
            "contactDelivery": {
              "type": "string",
              "maxLength": 100
            },
            "deliveryAddress": {
              "type": "string",
              "maxLength": 100
            },
            "additionalPhone": {
              "type": "string",
              "maxLength": 12,
              "pattern": "\\d{3}-\\d{3}-\\d{4}"
            },
            "purchaseOrderDate": {
              "type": "string",
              "format": "date"
            },
            "purchaseOrderNumber": {
              "type": "string",
              "maxLength": 20
            },
            "internalCode": {
              "type": "string",
              "maxLength": 20
            },
            "responsibleForPayment": {
              "type": "string",
              "maxLength": 20
            },
            "additionalInformation": {
              "type": "string",
              "maxLength": 150
            }
          }
        },
        "additionalInformation": {
          "type": "object",
          "properties": {
            "shippingDate": {
              "type": "string",
              "format": "date"
            },
            "shipmentNumber": {
              "type": "string",
              "maxLength": 25
            },
            "containerNumber": {
              "type": "string",
              "maxLength": 100
            },
            "referenceNumber": {
              "type": "integer",
              "maxLength": 20
            },
            "grossWeight": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "netWeight": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "grossWeightUnit": {
              "type": "integer",
              "maxLength": 2
            },
            "unitNetWeight": {
              "type": "integer",
              "maxLength": 2
            },
            "bulkQuantity": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "bulkUnit": {
              "type": "integer",
              "maxLength": 2
            },
            "bulkVolume": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "unitVolume": {
              "type": "integer",
              "maxLength": 2
            }
          }
        },
        "transport": {
          "type": "object",
          "properties": {
            "driver": {
              "type": "string",
              "maxLength": 20
            },
            "transportDocument": {
              "type": "integer",
              "maxLength": 20
            },
            "file": {
              "type": "string",
              "maxLength": 20
            },
            "licensePlate": {
              "type": "string",
              "maxLength": 7
            },
            "transportationRoute": {
              "type": "string",
              "maxLength": 20
            },
            "transportationZone": {
              "type": "string",
              "maxLength": 20
            },
            "albaranNumber": {
              "type": "string",
              "maxLength": 20
            }
          }
        },
        "totals": {
          "type": "object",
          "required": [
            "totalAmount"
          ],
          "properties": {
            "totalTaxedAmount": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "i1AmountTaxed": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "i2AmountTaxed": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "i3AmountTaxed": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "exemptAmount": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbisS1": {
              "type": "integer",
              "maxLength": 2,
              "minimum": 0
            },
            "itbisS2": {
              "type": "integer",
              "maxLength": 2,
              "minimum": 0
            },
            "itbisS3": {
              "type": "integer",
              "maxLength": 2,
              "minimum": 0
            },
            "itbisTotal": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbis1Total": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbis2Total": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbis3Total": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "additionalTaxAmount": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "additionalTaxes": {
              "type": "array",
              "maxItems": 20,
              "items": {
                "type": "object",
                "required": [
                  "taxType"
                ],
                "properties": {
                  "taxType": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 39
                  },
                  "additionalTaxRate": {
                    "type": "number",
                    "multipleOf": 0.01,
                    "minimum": 0,
                    "maximum": 999.99
                  },
                  "selectiveTaxAmountSpecificConsumption": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  },
                  "amountSelectiveConsumptionTaxAdvalorem": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  },
                  "otherAdditionalTaxes": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  }
                }
              }
            },
            "totalAmount": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "nonBillableAmount": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "amountPeriod": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "previousBalance": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "amountAdvancePayment": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "payValue": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbisTotalRetained": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "isrTotalRetention": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbisTotalPerception": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "isrTotalPerception": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            }
          }
        },
        "otherCurrency": {
          "type": "object",
          "required": [
            "currencyType",
            "exchangeRate",
            "totalAmountOtherCurrency"
          ],
          "properties": {
            "currencyType": {
              "type": "string",
              "enum": [
                "BRL",
                "CAD",
                "CHF",
                "CHY",
                "XDR",
                "DKK",
                "EUR",
                "GBP",
                "JPY",
                "NOK",
                "SCP",
                "SEK",
                "USD",
                "VEF"
              ]
            },
            "exchangeRate": {
              "type": "number",
              "maxLength": 7,
              "minimum": 0,
              "multipleOf": 0.0001
            },
            "totalTaxedAmountOtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "amountTaxed1OtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "amountTaxed2OtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "amountTaxed3OtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "exemptAmountOtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbisTotalOtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbis1TotalOtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbis2TotalOtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "itbis3TotalOtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "additionalTaxAmountOtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            },
            "additionalTaxesOtherCurrency": {
              "type": "array",
              "maxItems": 20,
              "items": {
                "type": "object",
                "required": [
                  "taxTypeOtherCurrency"
                ],
                "properties": {
                  "taxTypeOtherCurrency": {
                    "type": "integer",
                    "minimum": 1,
                    "maximum": 39
                  },
                  "additionalTaxRateOtherCurrency": {
                    "type": "number",
                    "multipleOf": 0.01,
                    "minimum": 0,
                    "maximum": 999.99
                  },
                  "selectiveTaxAmountSpecificConsumptionOtherCurrency": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  },
                  "amountSelectiveConsumptionTaxAdvaloremOtherCurrency": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  },
                  "otherAdditionalTaxesOtherCurrency": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  }
                }
              }
            },
            "totalAmountOtherCurrency": {
              "type": "number",
              "minimum": 0,
              "multipleOf": 0.01,
              "maxLength": 19,
              "maximum": 10000000000000000
            }
          }
        },
        "itemDetails": {
          "type": "array",
          "minItems": 1,
          "maxItems": 1000,
          "items": {
            "type": "object",
            "required": [
              "lineNumber",
              "billingIndicator",
              "itemName",
              "goodServiceIndicator",
              "quantityItem",
              "unitPriceItem",
              "itemAmount"
            ],
            "properties": {
              "lineNumber": {
                "type": "integer"
              },
              "itemCodeTable": {
                "type": "array",
                "maxItems": 5,
                "items": {
                  "type": "object",
                  "properties": {
                    "codeType": {
                      "type": "string",
                      "maxLength": 14
                    },
                    "itemCode": {
                      "type": "string"
                    }
                  }
                }
              },
              "billingIndicator": {
                "type": "integer",
                "maxLength": 1,
                "enum": [
                  0,
                  1,
                  2,
                  3,
                  4
                ]
              },
              "retention": {
                "type": "object",
                "properties": {
                  "indicatorAgentWithholdingPerception": {
                    "type": "integer",
                    "enum": [
                      1,
                      2
                    ]
                  },
                  "itbisAmountWithheld": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  },
                  "isrAmountWithheld": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  }
                }
              },
              "itemName": {
                "type": "string",
                "maxLength": 80
              },
              "goodServiceIndicator": {
                "type": "integer",
                "enum": [
                  1,
                  2
                ]
              },
              "itemDescription": {
                "type": "string",
                "maxLength": 1000
              },
              "quantityItem": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "unitMeasure": {
                "type": "integer",
                "minimum": 1,
                "maximum": 62
              },
              "quantityReference": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "referenceUnit": {
                "type": "integer",
                "maxLength": 2
              },
              "subquantityTable": {
                "type": "array",
                "maxItems": 5,
                "items": {
                  "type": "object",
                  "properties": {
                    "subquantity": {
                      "type": "number",
                      "minimum": 0,
                      "multipleOf": 0.001,
                      "maxLength": 19
                    },
                    "codeSubquantity": {
                      "type": "integer",
                      "minimum": 0,
                      "maxLength": 2
                    }
                  }
                }
              },
              "degreesAlcohol": {
                "type": "number",
                "maxLength": 6,
                "maximum": 99,
                "minimum": 0,
                "multipleOf": 0.001
              },
              "unitPriceReference": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "elaborationDate": {
                "type": "string",
                "format": "date"
              },
              "expirationDateItem": {
                "type": "string",
                "format": "date"
              },
              "mining": {
                "type": "object",
                "properties": {
                  "netWeightKilogram": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.001,
                    "maxLength": 19
                  },
                  "netWeightMining": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.001,
                    "maxLength": 19
                  },
                  "affiliationType": {
                    "type": "integer",
                    "enum": [
                      1,
                      2
                    ]
                  },
                  "settlement": {
                    "type": "integer",
                    "enum": [
                      1,
                      2
                    ]
                  }
                }
              },
              "unitPriceItem": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.0001,
                "maxLength": 21,
                "maximum": 1000000000000000000
              },
              "discountAmount": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subDiscounts": {
                "type": "array",
                "maxItems": 12,
                "items": {
                  "type": "object",
                  "properties": {
                    "subDiscountRate": {
                      "type": "string",
                      "enum": [
                        "$",
                        "%"
                      ]
                    },
                    "subDiscountPercentage": {
                      "type": "number",
                      "maxLength": 5,
                      "minimum": 0,
                      "multipleOf": 0.01
                    },
                    "subDiscountAmount": {
                      "type": "number",
                      "minimum": 0,
                      "multipleOf": 0.01,
                      "maxLength": 19,
                      "maximum": 10000000000000000
                    }
                  }
                }
              },
              "surchargeAmount": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subSurcharge": {
                "type": "array",
                "maxItems": 12,
                "items": {
                  "type": "object",
                  "properties": {
                    "subSurchargeType": {
                      "type": "string",
                      "enum": [
                        "$",
                        "%"
                      ]
                    },
                    "subSurchargePercentage": {
                      "type": "number",
                      "maxLength": 5,
                      "minimum": 0,
                      "multipleOf": 0.01
                    },
                    "subSurchargeAmount": {
                      "type": "number",
                      "minimum": 0,
                      "multipleOf": 0.01,
                      "maxLength": 19,
                      "maximum": 10000000000000000
                    }
                  }
                }
              },
              "additionalTaxes": {
                "type": "array",
                "maxItems": 2,
                "items": {
                  "type": "object",
                  "required": [
                    "taxType"
                  ],
                  "properties": {
                    "taxType": {
                      "type": "integer",
                      "minimum": 1,
                      "maximum": 39
                    }
                  }
                }
              },
              "otherCurrencyDetail": {
                "type": "object",
                "required": [
                  "priceOtherCurrency",
                  "amountItemOtherCurrency"
                ],
                "properties": {
                  "priceOtherCurrency": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.0001,
                    "maxLength": 21,
                    "maximum": 1000000000000000000
                  },
                  "discountOtherCurrency": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  },
                  "surchargeAnotherCurrency": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  },
                  "amountItemOtherCurrency": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  }
                }
              },
              "itemAmount": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              }
            }
          }
        },
        "subtotals": {
          "type": "array",
          "maxItems": 20,
          "items": {
            "type": "object",
            "properties": {
              "subTotalNumber": {
                "type": "integer",
                "maxLength": 2
              },
              "subtotalDescription": {
                "type": "string",
                "maxLength": 40
              },
              "order": {
                "type": "integer",
                "maxLength": 2
              },
              "subTotalAmountTaxedTotal": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subTotalAmountTaxedI1": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subTotalAmountTaxedI2": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subTotalAmountTaxedI3": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "itbisSubTotal": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "itbis1SubTotal": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "itbis2SubTotal": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "itbis3SubTotal": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subTotalAdditionalTax": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subTotalExempt": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subTotalAmount": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "lines": {
                "type": "integer",
                "maxLength": 2
              }
            }
          }
        },
        "discountsOrSurcharges": {
          "type": "array",
          "maxItems": 20,
          "items": {
            "type": "object",
            "properties": {
              "lineNumber": {
                "type": "integer",
                "maxLength": 2
              },
              "fitType": {
                "type": "string",
                "maxLength": 1,
                "enum": [
                  "D",
                  "R"
                ]
              },
              "norma1007Indicator": {
                "type": "integer",
                "maxLength": 1
              },
              "descriptionDiscountOrSurcharge": {
                "type": "string",
                "maxLength": 45
              },
              "typeValue": {
                "type": "string",
                "maxLength": 1,
                "enum": [
                  "%",
                  "$"
                ]
              },
              "discountValueOrSurcharge": {
                "type": "number",
                "maxLength": 6,
                "maximum": 999,
                "minimum": 0,
                "multipleOf": 0.01
              },
              "discountAmountOrSurcharge": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "discountAmountOrSurchargeOtherCurrency": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "indicatorBillingDiscountOrSurcharge": {
                "type": "integer",
                "maxLength": 1
              }
            }
          }
        },
        "pagination": {
          "type": "array",
          "minItems": 2,
          "maxItems": 100,
          "items": {
            "type": "object",
            "properties": {
              "pageNo": {
                "type": "integer",
                "maxLength": 3,
                "minimum": 0
              },
              "noLineFrom": {
                "type": "integer",
                "maxLength": 3,
                "minimum": 0
              },
              "noLineUntil": {
                "type": "integer",
                "maxLength": 3,
                "minimum": 0
              },
              "subtotalAmountTaxedPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subtotalAmountTaxed1Page": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subtotalAmountTaxed2Page": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subtotalAmountTaxed3Page": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "exemptSubtotalPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "itbisSubtotalPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "itbis1SubtotalPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "itbis2SubtotalPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "itbis3SubtotalPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subtotalAdditionalTaxPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subtotalAdditionalTax": {
                "type": "object",
                "properties": {
                  "subtotalSelectiveTaxForSpecificConsumptionPage": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  },
                  "subtotalOtherTax": {
                    "type": "number",
                    "minimum": 0,
                    "multipleOf": 0.01,
                    "maxLength": 19,
                    "maximum": 10000000000000000
                  }
                }
              },
              "subtotalAmountPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              },
              "subtotalNonBillableAmountPage": {
                "type": "number",
                "minimum": 0,
                "multipleOf": 0.01,
                "maxLength": 19,
                "maximum": 10000000000000000
              }
            }
          }
        },
        "informationReference": {
          "type": "object",
          "required": [
            "ncfModified",
            "modificationCode",
            "ncfModifiedDate"
          ],
          "properties": {
            "ncfModified": {
              "type": "string",
              "maxLength": 19,
              "pattern": "^(?!E33|E34).*$"
            },
            "rncOtherTaxpayer": {
              "type": "string",
              "maxLength": 11
            },
            "ncfModifiedDate": {
              "type": "string",
              "format": "date"
            },
            "modificationCode": {
              "type": "integer",
              "enum": [
                1,
                2,
                3,
                4
              ]
            },
            "reasonForModification": {
              "type": "string",
              "maxLength": 90
            }
          }
        },
        "config": {
          "type": "object",
          "properties": {
            "pdf": {
              "type": "object",
              "properties": {
                "type": {
                  "type": "string",
                  "enum": [
                    "generic",
                    "pos"
                  ]
                },
                "note": {
                  "type": "string",
                  "maxLength": 250
                }
              }
            }
          }
        }
      }
    },
    "responses": {
      "201": {
        "type": "object",
        "properties": {
          "id": {
            "type": "string",
            "format": "ulid"
          },
          "stampDate": {
            "type": "string",
            "format": "date"
          },
          "status": {
            "type": "string",
            "enum": [
              "REGISTERED",
              "TO_SEND",
              "WAITING_RESPONSE",
              "TO_NOTIFY",
              "FINISHED"
            ]
          },
          "companyIdentification": {
            "type": "string"
          },
          "encf": {
            "type": "string"
          },
          "pdf": {
            "type": "string",
            "format": "uri"
          },
          "documentStampUrl": {
            "type": "string",
            "format": "uri"
          },
          "signatureDate": {
            "type": "string",
            "format": "date-time"
          },
          "securityCode": {
            "type": "string"
          },
          "sequenceConsumed": {
            "type": "boolean"
          }
        }
      },
      "400": {
        "type": "object",
        "properties": {
          "code": {
            "type": "string"
          },
          "message": {
            "type": "string"
          }
        }
      },
      "404": {
        "type": "object",
        "properties": {
          "code": {
            "type": "string"
          },
          "message": {
            "type": "string"
          }
        }
      },
      "500": {
        "type": "object",
        "properties": {
          "code": {
            "type": "string"
          },
          "message": {
            "type": "string"
          }
        }
      }
    }
  }
};
