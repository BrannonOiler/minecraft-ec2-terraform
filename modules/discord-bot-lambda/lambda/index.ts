import {
  DescribeInstancesCommand,
  EC2Client,
  InstanceStateName,
  StartInstancesCommand,
  StopInstancesCommand,
} from "@aws-sdk/client-ec2";
import { APIGatewayProxyEvent, APIGatewayProxyResult } from "aws-lambda";
import {
  InteractionResponseType,
  InteractionType,
  verifyKey,
} from "discord-interactions";

//# ENVIRONMENT VARIABLES
const DISCORD_PUBLIC_KEY = process.env.DISCORD_PUBLIC_KEY ?? undefined;
const INSTANCE_ID = process.env.INSTANCE_ID ?? undefined;
const AWS_REGION = process.env.AWS_REGION ?? "us-east-1";

//# AWS SDK CLIENTS
const ec2Client = new EC2Client({ region: AWS_REGION });

//# HELPER FUNCTIONS
const verifyRequest = async (event: APIGatewayProxyEvent) => {
  if (!DISCORD_PUBLIC_KEY) return false;

  const signature = event.headers["x-signature-ed25519"] ?? "";
  const timestamp = event.headers["x-signature-timestamp"] ?? "";
  const body = event.body ?? "";

  //? Verify the request signature
  return verifyKey(body, signature, timestamp, DISCORD_PUBLIC_KEY);
};

const startInstance = async (): Promise<void> => {
  const command = new StartInstancesCommand({ InstanceIds: [INSTANCE_ID!] });
  await ec2Client.send(command);
  console.log(`Started instance: ${INSTANCE_ID}`);
};

const stopInstance = async (): Promise<void> => {
  const command = new StopInstancesCommand({ InstanceIds: [INSTANCE_ID!] });
  await ec2Client.send(command);
  console.log(`Stopped instance: ${INSTANCE_ID}`);
};

//? Options are ["pending", "running", "shutting-down", "stopped", "stopping", "terminated", "unknown"]
const getInstanceStatus = async (): Promise<InstanceStateName | "unknown"> => {
  const command = new DescribeInstancesCommand({ InstanceIds: [INSTANCE_ID!] });
  const response = await ec2Client.send(command);

  const instance = response.Reservations?.[0]?.Instances?.[0];
  if (!instance) throw new Error(`Instance ${INSTANCE_ID} not found`);

  return instance.State?.Name ?? "unknown";
};

//# LAMBDA HANDLER
export const handler = async (
  event: APIGatewayProxyEvent,
): Promise<APIGatewayProxyResult> => {
  //? Verify required environment variables are set
  if (!DISCORD_PUBLIC_KEY || !INSTANCE_ID) {
    return {
      statusCode: 500,
      body: JSON.stringify({
        type: InteractionResponseType.CHANNEL_MESSAGE_WITH_SOURCE,
        data: { content: `An error occurred: Missing environment variables` },
      }),
    };
  }

  //? Verify request signature
  const isRequestValid = await verifyRequest(event);
  if (!isRequestValid) {
    console.warn("Invalid request signature");
    return {
      statusCode: 401,
      body: JSON.stringify({
        type: InteractionResponseType.CHANNEL_MESSAGE_WITH_SOURCE,
        data: { content: "An error occurred: Invalid request signature" },
      }),
    };
  }

  const { type, data } = JSON.parse(event.body ?? "{}");

  //? Handle PING
  if (type === InteractionType.PING) {
    console.log("Received PING interaction from Discord");
    return {
      statusCode: 200,
      body: JSON.stringify({ type: InteractionResponseType.PONG }),
    };
  }

  //? Handle commands
  if (type === InteractionType.APPLICATION_COMMAND) {
    try {
      const currentStatus = await getInstanceStatus();

      switch (data?.name) {
        //? Handle "start" command, checking current status to prevent improper state transitions
        case "start": {
          console.log("Received 'start' command");

          if (
            ["running", "pending"].includes(currentStatus) ||
            ["stopping", "shutting-down"].includes(currentStatus)
          ) {
            return {
              statusCode: 200,
              body: JSON.stringify({
                type: InteractionResponseType.CHANNEL_MESSAGE_WITH_SOURCE,
                data: {
                  content: ["running", "pending"].includes(currentStatus)
                    ? `⚠️ Server is already ${currentStatus}`
                    : `⚠️ Server is ${currentStatus}, please wait before starting`,
                },
              }),
            };
          }

          await startInstance();
          return {
            statusCode: 200,
            body: JSON.stringify({
              type: InteractionResponseType.CHANNEL_MESSAGE_WITH_SOURCE,
              data: { content: "✅ Minecraft server is starting..." },
            }),
          };
        }

        //? Handle "stop" command, checking current status to prevent improper state transitions
        case "stop": {
          console.log("Received 'stop' command");

          if (
            [
              "stopped",
              "terminated",
              "stopping",
              "shutting-down",
              "pending",
            ].includes(currentStatus)
          ) {
            return {
              statusCode: 200,
              body: JSON.stringify({
                type: InteractionResponseType.CHANNEL_MESSAGE_WITH_SOURCE,
                data: {
                  content:
                    currentStatus === "pending"
                      ? `⚠️ Server is ${currentStatus}, please wait before stopping`
                      : `⚠️ Server is already ${currentStatus}`,
                },
              }),
            };
          }

          await stopInstance();
          return {
            statusCode: 200,
            body: JSON.stringify({
              type: InteractionResponseType.CHANNEL_MESSAGE_WITH_SOURCE,
              data: { content: "🛑 Minecraft server is stopping..." },
            }),
          };
        }

        //? Handle "status" command
        case "status": {
          console.log("Received 'status' command");
          const state = await getInstanceStatus();
          let emoji = "⚪";
          if (state === "running") emoji = "🟢";
          else if (["stopped", "terminated"].includes(state)) emoji = "🔴";
          else if (["pending", "shutting-down", "stopping"].includes(state))
            emoji = "🟡";

          return {
            statusCode: 200,
            body: JSON.stringify({
              type: InteractionResponseType.CHANNEL_MESSAGE_WITH_SOURCE,
              data: { content: `${emoji} Server status: **${state}**` },
            }),
          };
        }

        default: {
          console.warn(`Unknown command: ${data?.name}`);
          return {
            statusCode: 400,
            body: JSON.stringify({
              type: InteractionResponseType.CHANNEL_MESSAGE_WITH_SOURCE,
              data: { content: `Unknown command: ${data?.name}` },
            }),
          };
        }
      }
    } catch (error) {
      const errorMessage =
        error instanceof Error ? error.message : "Unknown error";
      console.error("Error handling command:", errorMessage);
      return {
        statusCode: 500,
        body: JSON.stringify({
          type: InteractionResponseType.CHANNEL_MESSAGE_WITH_SOURCE,
          data: { content: `❌ Error: ${errorMessage}` },
        }),
      };
    }
  }

  return {
    statusCode: 400,
    body: JSON.stringify({
      type: InteractionResponseType.CHANNEL_MESSAGE_WITH_SOURCE,
      data: { content: "An error occurred: Unsupported interaction type" },
    }),
  };
};
