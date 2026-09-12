// Define la lógica para cada tipo de evento
import { SESClient, SendEmailCommand } from "@aws-sdk/client-ses";

// Inicializar el cliente de SES (disponible nativamente en el runtime de Node.js de Lambda)
const sesClient = new SESClient({});

export const userRegistrationHandler = async (payload) => {
  // Extraemos el email dinámico que viene en el cuerpo del mensaje
  const destinationEmail = payload.email;
  const senderEmail = process.env.SENDER_EMAIL;

  console.log(`Starting SES email delivery for: ${destinationEmail}`);

  if (!destinationEmail) {
    throw new Error("The payload does not contain the 'email' property.");
  }

  // Configuración del correo para SES
  const params = {
    Source: senderEmail, // El remitente configurado en Terraform
    Destination: {
      ToAddresses: [destinationEmail] // El destinatario dinámico del SQS
    },
    Message: {
      Subject: {
        Data: "Welcome to Our Platform!",
        Charset: "UTF-8"
      },
      Body: {
        Text: {
          Data: `Hello ${payload.name || "there"},\n\nThank you for registering with our platform.`,
          Charset: "UTF-8"
        },
        Html: {
          Data: `
            <div style="font-family: sans-serif; padding: 20px; border: 1px solid #eee;">
              <h2 style="color: #333;">Welcome, ${payload.name || "there"}!</h2>
              <p>Thank you for registering with our platform.</p>
              <p><strong>Your confirmation code is:</strong> ${payload.otp}</p>
              <br>
              <small>This is an automated email. Please do not reply.</small>
            </div>
          `,
          Charset: "UTF-8"
        }
      }
    }
  };

  try {
    const command = new SendEmailCommand(params);
    const response = await sesClient.send(command);

    console.log(
      `Email sent successfully via SES. MessageId: ${response.MessageId}`
    );
    return response;
  } catch (error) {
    console.error("Error sending the email with AWS SES:", error);
    throw error;
  }
};

export const otpResendHandler = async (payload) => {
  const destinationEmail = payload.email;
  const senderEmail = process.env.SENDER_EMAIL;

  console.log(`Starting OTP resend for: ${destinationEmail}`);

  // Validaciones básicas de seguridad del payload
  if (!destinationEmail || !payload.otp) {
    throw new Error("Required payload data is missing (email or OTP).");
  }

  const params = {
    Source: senderEmail,
    Destination: {
      ToAddresses: [destinationEmail]
    },
    Message: {
      Subject: {
        Data: `${payload.otp} is your verification code`,
        Charset: "UTF-8"
      },
      Body: {
        Html: {
          Data: `
            <div style="font-family: Arial, sans-serif; max-width: 500px; margin: 0 auto; padding: 20px; border: 1px solid #e0e0e0; border-radius: 8px;">
              <h2 style="color: #222; text-align: center;">Verification Code (OTP)</h2>
              <p style="color: #555; font-size: 16px;">Hello ${payload.name || "there"},</p>
              <p style="color: #555; font-size: 16px;">You requested a new code to verify your identity. Use the following security code:</p>
              
              <div style="background-color: #f4f4f9; padding: 15px; text-align: center; border-radius: 6px; margin: 25px 0;">
                <span style="font-size: 32px; font-weight: bold; letter-spacing: 4px; color: #1a73e8;">${payload.otp}</span>
              </div>
              
              <p style="color: #888; font-size: 14px; text-align: center;">
                This code expires in <strong>${payload.expirationMinutes || 5} minutes</strong>.<br>
                If you did not request this code, you can safely ignore this email.
              </p>
            </div>
          `,
          Charset: "UTF-8"
        },
        Text: {
          Data: `Hello ${payload.name || "there"},\n\nYour verification code is: ${payload.otp}.\n\nThis code expires in ${payload.expirationMinutes || 5} minutes.`,
          Charset: "UTF-8"
        }
      }
    }
  };

  try {
    const command = new SendEmailCommand(params);
    const response = await sesClient.send(command);

    console.log(
      `OTP resent successfully via SES. MessageId: ${response.MessageId}`
    );
    return response;
  } catch (error) {
    console.error("Error sending the OTP with AWS SES:", error);
    throw error;
  }
};
export const transactionConfirmationHandler = async (payload) => {
  const destinationEmail = payload.email;
  const senderEmail = process.env.SENDER_EMAIL;
  const orderNumber = payload.transactionNumber;
  console.log(`Starting donation confirmation email for: ${destinationEmail}`);

  if (!destinationEmail || !orderNumber) {
    throw new Error(
      "Required payload data is missing (email or order number)."
    );
  }

  const donorName = payload.name || "there";
  const params = {
    Source: senderEmail,
    Destination: {
      ToAddresses: [destinationEmail]
    },
    Message: {
      Subject: {
        Data: "Thank you for your donation",
        Charset: "UTF-8"
      },
      Body: {
        Text: {
          Data: `Hello ${donorName},\n\nThank you for your donation.`,
          Charset: "UTF-8"
        },
        Html: {
          Data: `
            <div style="font-family: Arial, sans-serif; max-width: 560px; margin: 0 auto; padding: 28px; color: #333; border: 1px solid #e5e5e5; border-radius: 8px;">
              <h2 style="color: #222; margin-top: 0;">Thank you for your donation, ${donorName}!</h2>
              <p>Your gift for the children has been successfully confirmed.</p>
              <p>Because of your generosity, the children will be blessed.</p>
              <div style="background-color: #f5f7fa; padding: 16px; margin: 24px 0; border-radius: 6px;">
                <strong>Order number</strong><br>
                <span style="font-size: 20px; letter-spacing: 1px; color: #1a73e8;">${orderNumber}</span>
              </div>
              <p style="color: #777; font-size: 13px;">Please keep this email for your records.</p>
            </div>
          `,
          Charset: "UTF-8"
        }
      }
    }
  };

  try {
    const command = new SendEmailCommand(params);
    const response = await sesClient.send(command);

    console.log(
      `Donation confirmation sent successfully via SES. MessageId: ${response.MessageId}`
    );
    return response;
  } catch (error) {
    console.error(
      "Error sending the donation confirmation with AWS SES:",
      error
    );
    throw error;
  }
};
