// Define la lógica para cada tipo de evento
import { SESClient, SendEmailCommand } from "@aws-sdk/client-ses";

// Inicializar el cliente de SES (disponible nativamente en el runtime de Node.js de Lambda)
const sesClient = new SESClient({});

export const userRegistrationHandler = async (payload) => {
  // Extraemos el email dinámico que viene en el cuerpo del mensaje
  const destinationEmail = payload.email;
  const senderEmail = process.env.SENDER_EMAIL;

  console.log(`Iniciando envío de email SES para: ${destinationEmail}`);

  if (!destinationEmail) {
    throw new Error("El payload no contiene la propiedad 'email'.");
  }

  // Configuración del correo para SES
  const params = {
    Source: senderEmail, // El remitente configurado en Terraform
    Destination: {
      ToAddresses: [destinationEmail] // El destinatario dinámico del SQS
    },
    Message: {
      Subject: {
        Data: "¡Bienvenido a Nuestra Plataforma!",
        Charset: "UTF-8"
      },
      Body: {
        // Puedes enviar Texto Plano
        Text: {
          Data: `Hola ${payload.name || "Usuario"},\n\nGracias por registrarte.`,
          Charset: "UTF-8"
        },
        // O puedes enviar HTML si quieres un diseño más profesional
        Html: {
          Data: `
            <div style="font-family: sans-serif; padding: 20px; border: 1px solid #eee;">
              <h2 style="color: #333;">¡Bienvenido, ${payload.name || "Usuario"}!</h2>
              <p>Gracias por registrarte en nuestra plataforma.</p>
              <p><strong>Tu ID de confirmación es:</strong> ${payload.otp}</p>
              <br>
              <small>Este es un correo automático, por favor no respondas.</small>
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
      `Email enviado con éxito vía SES. MessageId: ${response.MessageId}`
    );
    return response;
  } catch (error) {
    console.error("Error al enviar el correo con AWS SES:", error);
    throw error; // Lanza el error para que SQS reintente el mensaje si falla
  }
};

export const otpResendHandler = async (payload) => {
  const destinationEmail = payload.email;
  const senderEmail = process.env.SENDER_EMAIL;

  console.log(`Iniciando reenvío de OTP para: ${destinationEmail}`);

  // Validaciones básicas de seguridad del payload
  if (!destinationEmail || !payload.otp) {
    throw new Error("Faltan datos mandatorios en el payload (email o otp).");
  }

  const params = {
    Source: senderEmail,
    Destination: {
      ToAddresses: [destinationEmail]
    },
    Message: {
      Subject: {
        Data: `${payload.otp} es tu código de verificación`,
        Charset: "UTF-8"
      },
      Body: {
        Html: {
          Data: `
            <div style="font-family: Arial, sans-serif; max-width: 500px; margin: 0 auto; padding: 20px; border: 1px solid #e0e0e0; border-radius: 8px;">
              <h2 style="color: #222; text-align: center;">Código de Verificación (OTP)</h2>
              <p style="color: #555; font-size: 16px;">Hola ${payload.name || "Usuario"},</p>
              <p style="color: #555; font-size: 16px;">Has solicitado un nuevo código para verificar tu identidad. Usa el siguiente código de seguridad:</p>
              
              <!-- Contenedor del Código OTP -->
              <div style="background-color: #f4f4f9; padding: 15px; text-align: center; border-radius: 6px; margin: 25px 0;">
                <span style="font-size: 32px; font-weight: bold; letter-spacing: 4px; color: #1a73e8;">${payload.otp}</span>
              </div>
              
              <p style="color: #888; font-size: 14px; text-align: center;">
                Este código expira en <strong>${payload.expirationMinutes || 5} minutos</strong>.<br>
                Si tú no solicitaste este código, puedes ignorar este correo de forma segura.
              </p>
            </div>
          `,
          Charset: "UTF-8"
        },
        Text: {
          Data: `Hola ${payload.name || "Usuario"},\n\nTu código de verificación es: ${payload.otp}.\n\nEste código expira en ${payload.expirationMinutes || 5} minutos.`,
          Charset: "UTF-8"
        }
      }
    }
  };

  try {
    const command = new SendEmailCommand(params);
    const response = await sesClient.send(command);

    console.log(
      `OTP reenviado con éxito vía SES. MessageId: ${response.MessageId}`
    );
    return response;
  } catch (error) {
    console.error("Error al enviar el OTP con AWS SES:", error);
    throw error; // Permite que SQS reintente si hay una falla intermitente de AWS
  }
};
