import { userRegistrationHandler, otpResendHandler } from "./handlers.js";

// Diccionario que mapea el string del eventType con su función correspondiente
const EVENT_REGISTRY = {
  USER_REGISTRATION: userRegistrationHandler,
  OTP_RESEND: otpResendHandler
};

export const handler = async (event) => {
  // SQS siempre envía un array de Records (según el batch_size configurado)
  for (const record of event.Records) {
    try {
      // 1. Parsear el cuerpo del mensaje de SQS
      const body = JSON.parse(record.body);
      const { eventType, payload } = body;

      console.log(
        `Recibido evento tipo: ${eventType} con ID de mensaje: ${record.messageId}`
      );

      // 2. Buscar el handler correspondiente
      const processEvent = EVENT_REGISTRY[eventType];

      if (processEvent) {
        // 3. Ejecutar la estrategia si existe
        await processEvent(payload);
      } else {
        // 4. Manejar tipos de eventos no soportados o desconocidos
        console.warn(
          `Advertencia: Tipo de evento no soportado '${eventType}'. Saltando mensaje.`
        );
        // Dependiendo de tu negocio, aquí podrías lanzar un error para mandarlo a una DLQ
      }
    } catch (error) {
      console.error(`Error procesando el mensaje ${record.messageId}:`, error);
      // Lanzar el error hace que SQS no borre este mensaje específico del lote
      throw error;
    }
  }
};
