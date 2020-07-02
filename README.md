# Control a Dumb Garage Door Remote with Alexa

Garage door openers that work with Alexa are pretty expensive, so I decided to turn my existing dumb garage door remote into a smart one that can be controlled by Alexa using a [Raspberry Pi](https://www.amazon.com/s?k=raspberry+pi). 

![](https://github.com/kylekyle/alexa-garage/raw/master/images/works-with-alexa.png)

I started this project to learn more about AWS IoT devices and Alexa skills. If you aren't interested in writing your own skill or creating an AWS IoT device, then check out **[Sinric](https://github.com/kakopappa/sinric)** which is free and appears to be a *much* easier way to control your device with Alexa. If, on the other hand, you *do* want to get your hands dirty, then read on!

## Create an AWS IoT device

Follow Amazon's [Getting started with AWS IoT Core](https://docs.aws.amazon.com/iot/latest/developerguide/iot-gs.html) guide to create an AWS device. The guide is pretty straightforward, but the security policy can be tricky to get right. The following policy will make it a log easier to get up and running: 

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iot:*",
      "Resource": "*"
    }
  ]
}
```

Once everything is working, you can go back and tighten up the policy. When you do tighten up the policy, don't forget that your Lambda function will need explicit IoT publishing permission. 

## Connect the Raspberry Pi to your AWS IoT Device

The following is taken from the [Using the AWS IoT device SDKs on a Raspberry Pi](https://docs.aws.amazon.com/iot/latest/developerguide/sdk-tutorials.html) guide. If you get stuck, the guide is a good resource. 

Make sure you're running the latest [Raspberry Pi OS](https://www.raspberrypi.org/documentation/installation/installing-images/README.md) and can connect to the Internet.

First, clone this repo to the Raspberry Pi. This repo includes `aws-iot-device-sdk-embedded-C` as a submodule:

```bash
~ $ git clone https://github.com/kylekyle/alexa-garage -b release --recurse-submodules 
```

Copy the certificates for your AWS IoT device to `alexa-garage/raspberry-pi/certs`.

Next, download [mbed TLS](https://tls.mbed.org) and add it to the `aws-iot-device-sdk-embedded-C` external libs directory:

```bash
~ $ wget https://tls.mbed.org/download/mbedtls-2.16.6-apache.tgz
~ $ tar -xzf mbedtls-2.16.6-apache.tgz
~ $ mv mbedtls-2.16.6/* alexa-garage/raspberry-pi/aws-iot-device-sdk-embedded-c/external_libs/mbedTLS/
```

Update the define statements at the top of `alexa-garage/raspberry-pi/aws_iot_config.h` with the values for your AWS IoT device. It should look something like this: 

```c++
// ================================================
#define AWS_IOT_MQTT_HOST              "a22j5sm6o3yzc5.iot.us-east-1.amazonaws.com"
#define AWS_IOT_MQTT_PORT              8883
#define AWS_IOT_MQTT_CLIENT_ID         "MyRaspberryPi"
#define AWS_IOT_MY_THING_NAME          "MyRaspberryPi"
#define AWS_IOT_ROOT_CA_FILENAME       "AmazonRootCA1.pem"
#define AWS_IOT_CERTIFICATE_FILENAME   "device.pem.crt"
#define AWS_IOT_PRIVATE_KEY_FILENAME   "private.pem.key"
// ================================================= 
```

Finally, run `make` in the `alexa-garage/raspberry-pi` directory to build your executable. You should be able to run your executable and receive messages on the `garage/toggle/left` and `garage/toggle/right` topics. You can publish test messages to those topics from the AWS IoT console. 

If you want your service to start automatically when your pi boots, run the following: 

```bash
~ $ sudo cp alexa-garage/raspberry-pi/garage.service /etc/systemd/system/
~ $ sudo systemctl enable garage.service 
~ $ sudo service garage start
```

## Wire the Remote to the Raspberry Pi

Here's where we crack open the garage door opener. I feel obliged to issue the usual disclaimer: This could totally break your garage door remote. I had a spare remote, so it wasn't a big deal if the spare broke. Proceed at your own risk. 

I used alligator clips to wire my Chamberlain three-button remote to my Pi, but you would get better results soldering. Here's how I wired things up: 

![](https://github.com/kylekyle/alexa-garage/raw/master/images/wiring-diagram.jpg)

|   Name  | Physical pin | `wpi` pin |      Remote component     |
|:-------:|:------------:|:---------:|:-------------------------:|
|   3.3V  |       1      |           | Positive battery terminal |
|    0v   |      39      |           | Negative battery terminal |
| GPIO.25 |      27      |     25    |  Left garage door button  |
| GPIO.24 |      25      |     24    |  Right garage door button |

If your remote is like mine, you should attach the clip to either of the top pins on the buttons: 

![Button pins](https://github.com/kylekyle/alexa-garage/raw/master/images/button-pins.jpg)

If you use different pins make sure to update the pin constants at the top of the `alexa-garage/raspberry-pi/aws_iot_config.h` and re-compile. I use [wiringPi](http://wiringpi.com/) pin numbering. If you are looking for a diagram of the pin numbers for your board, try running `gpio readll` and look at the `wpi` column.   

## Create the IAM Role

Your Lambda will need an execution role. Head over to the [IAM console](https://console.aws.amazon.com/iam/home?#/roles$new) and create a role with the following policies: 

 - `AWSLambdaBasicExecutionRole` (for executing the Lambda)
 - `AWSIoTDataAccess` (for sending messages to the IoT device)

## Create the Lambda

Lambdas are what power smart home skills. When Alexa looks for new smart home devices or when you ask her to open or close the garage, those requests will be routed to your skill's Lambda. 

It is really important that you create your Lambda in the correct AWS region. Use the table below. If you put in the wrong (like the default region), it just won't work. 

|         Skill language         | Endpoint Region | Lambda Function Region |
|:------------------------------:|:---------------:|:----------------------:|
| English (US), English (Canada) | North America   | US East (N. Virginia)  |
| English (UK), German           | Europe          | EU (Ireland)           |
| English (India)                | India           | EU (Ireland)           |
| Japanese, English (Australia)  | Far East        | US West (Oregon)       |

- Login into your [AWS Lambda Dashboard](https://console.aws.amazon.com/Lambda/home).
- Click *Create Function* -> *Author from Scratch*. 
  - Give the Lambda any name you like. 
  - Choose the latest version of Ruby as your runtime.  
  - Assign the IAM Role you created in the previous step. 
  - Click *Create Function*
- Scroll down to the *Function Code* editor. Copy the contents of `alexa-garage/Lambda_function.rb` into `Lambda_function.rb` in the editor. 
  - Replace the `IOT_REGION` and `IOT_THING_REST_ENDPOINT` constants at the top of the file with the values for your AWS IoT Thing. 
  - By default, the `DISPLAY_CATEGORY` constant is set to `SWITCH`. If you change it to `GARAGE_DOOR`, then you have to manually activate voice control in the Alexa app and voice control requires you say a pin. It's more secure, but less convenient
- Click *Save*. Test your code by configuring an *Amazon Alexa Smart Home Discovery Request* test at the top and clicking *Test*.

## Setup Login with Amazon (LWA) 

Smart home skills require OAuth authentication. To configure your skill to use Amazon for authentication, head over to the [Login with Amazon Dashboard](https://developer.amazon.com/loginwithamazon/console/site/lwa/overview.html) and create a security profile: 

 - Click *Create a New Security Profile*
 - Enter a name and description for your profile. You are required to have a Privacy Notice URL. I entered `https://www.example.com/privacy.html` since my skill is just for personal use. 

## Create the Skill 

We finally have everything we need to create the Alexa Skill. Head over to the [Alexa Developer Console](https://developer.amazon.com/alexa/console/ask) and click *Create Skill*. 

 - Enter a name and language. Remember, your language must correspond to your Lambda's region in the table above. 
 - Choose the *Smart Home* model. 
 - Click *Create Skill* at the top. 
 - Under *Smart Home service endpoint*, enter your Lambda's ARN as the *Default endpoint*. The ARN is at the very top of your Lambda function page. 
 - Copy your skill's ARN, and head back over to your Lambda function page. At the top, click *Add trigger* -> *Alexa Smart Home* -> Enter your skill ARN under *Application ID*. This will trigger your Lambda whenever your skill is activated. 
 - Head back to your skill page, scroll to the bottom and click *Setup Account Linking* and fill in the following values:

| Field                                | Value                                                                                                                                                                                      |
|--------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Authorization URI                    | https://www.amazon.com/ap/oa                                                                                                                                                               |
| Access Token URI                     | https://api.amazon.com/auth/o2/token                                                                                                                                                       |
| Your Client ID                       | *Use the value from your [Login with Amazon Dashboard](https://developer.amazon.com/loginwithamazon/console/site/lwa/overview.html)*                                                       |
| Your Secret                          | *Use the value from your [Login with Amazon Dashboard](https://developer.amazon.com/loginwithamazon/console/site/lwa/overview.html)*                                                       |
| Your Authentication Scheme           | HTTP Basic                                                                                                                                                                                 |
| Scope                                | profile                                                                                                                                                                                    |
| Domain List                          | *Leave blank*                                                                                                                                                                              |
| Default Access Token Expiration Time | *Leave blank*                                                                                                                                                                              |
| Alexa Redirect URLs                  | *Copy these values into your [Login with Amazon Security Profile](https://developer.amazon.com/loginwithamazon/console/site/lwa/overview.html) as Allowed Redirect URLs under Web Setting* |

## Run the Skill

 - Head to the *Skills & Games* section in your Alexa app and click on *Your Skills*. 
 - Click on your skill and authenticate to Amazon. 
 - You should be prompted to *Discover New Devices*. You should see the *Left Garage Door* and *Right Garage Door* appear in your device list. 
 - Click on one of the garage devices and click *On* or *Off*. Since the devices implement the [ToggleController interface](https://developer.amazon.com/en-US/docs/alexa/device-apis/alexa-togglecontroller.html), both buttons do the same thing: They click the button on your garage door remote. 
 - There are a lot of moving parts, so you'll probably have to debug something. I recommend checking your [CloudWatch log](https://console.aws.amazon.com/cloudwatch/home) to see what messages Alexa is sending to your Lambda and what messages your Lambda is sending back. 

If you get stuck because of some lack of documentation here, shoot me a pull request and I'm happy to update. Feel free to submit issues if you have any questions. Good luck! 
