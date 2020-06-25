require 'aws-sdk'
require 'securerandom'

IOT_THING_REGION = '<your-iot-region>'
IOT_THING_REST_ENDPOINT = 'https://<your-iot-rest-endpoint>.iot.<your-region>.amazonaws.com'

# If you use GARAGE_DOOR, then you have to manually activate voice control 
# in the Alexa app and voice control requires you say a pin. It's more 
# secure, but less convenient
DISPLAY_CATEGORY = 'SWITCH' 

def lambda_handler(event:, context:)
  puts JSON.pretty_generate(event), "\n"
    
  response = case event.dig('directive', 'header', 'name')
  when 'Discover'
    discovery()
  when 'TurnOn', 'TurnOff'
    toggle(event: event)
  else
    error(message: 'unsupported directive')
  end
  
  puts JSON.pretty_generate(response), "\n"
  response
end

def toggle event:
  puts "Toggling garage door\n"
  
  instance = event.dig('directive', 'header', 'instance')
  endpointId = event.dig('directive', 'endpoint', 'endpointId')
  correlationToken = event.dig('directive', 'header', 'correlationToken')  
  
  client = Aws::IoTDataPlane::Client.new(
    region: IOT_THING_REGION, 
    endpoint: IOT_THING_REST_ENDPOINT
  )
  
  side = endpointId[/(left|right)/]
  
  client.publish({
  	topic: "garage/toggle/#{side}",
  	qos: 0,
  	payload: 'ON'
  })

  {
    event: {
      header: {
        namespace: "Alexa",
        name: "Response",
        messageId: SecureRandom.uuid,
        correlationToken: correlationToken,
        payloadVersion: "3"
      },
      endpoint: {
        endpointId: endpointId
      },
      payload: {}
    },
    context: {
      properties: [
        {
          namespace: "Alexa.ToggleController",
          instance: instance,
          name: "toggleState",
          value: "ON"
        }
      ]
    }
  }
end

def discovery
  puts "Sending discovery event"
  {
    event: {
      header: {
        payloadVersion: '3',
        name: 'Discover.Response',
        namespace: 'Alexa.Discovery',
        messageId: SecureRandom.uuid
      },
      payload: {
        endpoints: ['left', 'right'].map do |side|
          {
            endpointId: "garage-#{side}",
            manufacturerName: 'kylekyle',
            description: 'Hacked Garage Door Opener',
            friendlyName: "#{side.capitalize} Garage Door",
            displayCategories: [DISPLAY_CATEGORY],
            cookie: {},
            connections: [],
            relationships: {},
            additionalAttributes: {},
            capabilities: [
              {
                type: 'AlexaInterface',
                interface: 'Alexa.ToggleController',
                instance: side,
                version: '3',
                properties: {
                  supported: [
                    {
                      name: 'toggleState'
                    }
                  ],
                  proactivelyReported: false,
                  retrievable: false
                },
                capabilityResources: {
                  friendlyNames: [
                    {
                      '@type': 'text',
                      value: {
                        text: "#{side} garage door",
                        locale: 'en-US'
                      }
                    }
                  ]
                },
                semantics: {
                  actionMappings: [
                    {
                      '@type': 'ActionsToDirective',
                      actions: ['Alexa.Actions.Close'],
                      directive: {
                        name: 'TurnOff',
                        payload: {}
                      }
                    },
                    {
                      '@type': 'ActionsToDirective',
                      actions: ['Alexa.Actions.Open'],
                      directive: {
                        name: 'TurnOn',
                        payload: {}
                      }
                    }
                  ],
                  stateMappings: [
                    {
                      '@type': 'StatesToValue',
                      states: ['Alexa.States.Closed'],
                      value: 'OFF'
                    },
                    {
                      '@type': 'StatesToValue',
                      states: ['Alexa.States.Open'],
                      value: 'ON'
                    }  
                  ]
                }
              },
              {
                type: 'AlexaInterface',
                interface: 'Alexa',
                version: '3'
              }
            ]
          }
        end
      }
    }
  }
end

def error message:
  puts 'ERROR: Unsupported directive'
  {
    event: {
      header: {
        namespace: "Alexa",
        payloadVersion: "3",
        name: "ErrorResponse",
        messageId: SecureRandom.uuid
      },
      endpoint: {
        endpointId: "garage"
      },
      payload: {
        type: "INTERNAL_ERROR",
        message: message
      }
    }
  }
end