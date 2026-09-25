import { DynamoDBClient, PutItemCommand } from "@aws-sdk/client-dynamodb";
import {
  DescribeInstancesCommand,
  EC2Client,
  StartInstancesCommand,
} from "@aws-sdk/client-ec2";
import { SendCommandCommand, SSMClient } from "@aws-sdk/client-ssm";
import {
  MinecraftServer,
  serverFromInstance,
} from "./minecraft";

const INTERACTION_TTL_SECONDS = 900;

export const recordOnce = async (
  put: () => Promise<unknown>,
): Promise<boolean> => {
  try {
    await put();
    return true;
  } catch (error) {
    if (
      error instanceof Error &&
      error.name === "ConditionalCheckFailedException"
    ) {
      return false;
    }
    throw error;
  }
};

type AwsServicesOptions = {
  ec2Client: EC2Client;
  ssmClient: SSMClient;
  dynamoClient: DynamoDBClient;
  projectTag: string;
  interactionTable?: string;
};

export const createAwsServices = ({
  ec2Client,
  ssmClient,
  dynamoClient,
  projectTag,
  interactionTable,
}: AwsServicesOptions) => ({
  listServers: async (): Promise<MinecraftServer[]> => {
    const result = await ec2Client.send(
      new DescribeInstancesCommand({
        Filters: [
          { Name: "tag:Project", Values: [projectTag] },
          { Name: "tag:DiscordManaged", Values: ["true"] },
          {
            Name: "instance-state-name",
            Values: [
              "pending",
              "running",
              "shutting-down",
              "stopping",
              "stopped",
            ],
          },
        ],
      }),
    );

    return (
      result.Reservations?.flatMap(
        (reservation) => reservation.Instances ?? [],
      ) ?? []
    )
      .map(serverFromInstance)
      .filter((server) => server.key && server.instanceId)
      .sort((left, right) => left.key.localeCompare(right.key));
  },

  startServer: async (server: MinecraftServer): Promise<void> => {
    await ec2Client.send(
      new StartInstancesCommand({ InstanceIds: [server.instanceId] }),
    );
  },

  stopServerGracefully: async (server: MinecraftServer): Promise<void> => {
    await ssmClient.send(
      new SendCommandCommand({
        DocumentName: "AWS-RunShellScript",
        InstanceIds: [server.instanceId],
        Comment: `Discord graceful shutdown for ${server.key}`,
        TimeoutSeconds: 900,
        Parameters: {
          commands: [
            "set -euo pipefail",
            "systemctl stop minecraft.service",
            "sync",
            "shutdown -h now",
          ],
        },
      }),
    );
  },

  recordInteraction: async (interactionId: string): Promise<boolean> => {
    if (!interactionTable) {
      throw new Error("Missing DISCORD_INTERACTION_TABLE.");
    }
    const expiresAt = Math.floor(Date.now() / 1000) + INTERACTION_TTL_SECONDS;
    return recordOnce(() =>
      dynamoClient.send(
        new PutItemCommand({
          TableName: interactionTable,
          Item: {
            interaction_id: { S: interactionId },
            expires_at: { N: String(expiresAt) },
          },
          ConditionExpression: "attribute_not_exists(interaction_id)",
        }),
      ),
    );
  },
});
