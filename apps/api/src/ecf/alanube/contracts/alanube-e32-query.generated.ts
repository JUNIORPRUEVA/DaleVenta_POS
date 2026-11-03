// Generated from hash-pinned official DOM GET schemas. Do not hand-edit.
export const ALANUBE_E32_QUERY: Record<string, { source: string; sourceSha256: string; endpoint: string; schemaSha256: string; responses: Record<string, Record<string, unknown>> }> = {
  "checkinvoices": {
    "source": "https://developer.alanube.co/reference/checkinvoices",
    "sourceSha256": "F55DB04BD29C0EA53A51219492F8F3A573652137F426A0CBCEBB9BC15EAB4201",
    "endpoint": "/invoices/{id}",
    "schemaSha256": "5443aeddd56e0b10bd9d7c159a0604093813953c521707b1993b33734d118d50",
    "responses": {
      "200": {
        "allOf": [
          {
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
              "trackId": {
                "type": "string",
                "format": "uuid"
              },
              "documentNumber": {
                "type": "string"
              },
              "documentStampUrl": {
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
              }
            }
          },
          {
            "type": "object",
            "properties": {
              "resumeXml": {
                "type": "string",
                "format": "uri"
              }
            }
          }
        ]
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
  "checkinvoicesbycompany": {
    "source": "https://developer.alanube.co/reference/checkinvoicesbycompany",
    "sourceSha256": "0E783B1977A7545C83058B689186385ED78CC8697F9A036FF3364D6A994941E2",
    "endpoint": "/invoices/{id}/idCompany/{idCompany}",
    "schemaSha256": "5443aeddd56e0b10bd9d7c159a0604093813953c521707b1993b33734d118d50",
    "responses": {
      "200": {
        "allOf": [
          {
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
              "trackId": {
                "type": "string",
                "format": "uuid"
              },
              "documentNumber": {
                "type": "string"
              },
              "documentStampUrl": {
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
              }
            }
          },
          {
            "type": "object",
            "properties": {
              "resumeXml": {
                "type": "string",
                "format": "uri"
              }
            }
          }
        ]
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
