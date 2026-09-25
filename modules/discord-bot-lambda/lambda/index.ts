import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { EC2Client } from "@aws-sdk/client-ec2";
import { SSMClient } from "@aws-sdk/client-ssm";
import { verifyKey } from "discord-interactions";
import { createCommandHandlers } from "./commands";
import { createInteractionHandler } from "./discord";
import { createAwsServices } from "./services";

const DISCORD_PUBLIC_KEY = process.env.DISCORD_PUBLIC_KEY;
const PROJECT_TAG = process.env.SERVER_PROJECT_TAG_VALUE ?? "minecraft-server";
const ALLOWED_GUILD_ID = process.env.ALLOWED_GUILD_ID || undefined;
const INTERACTION_TABLE = process.env.DISCORD_INTERACTION_TABLE;
const AWS_REGION = process.env.AWS_REGION ?? "us-east-1";

const services = createAwsServices({
  ec2Client: new EC2Client({ region: AWS_REGION }),
  ssmClient: new SSMClient({ region: AWS_REGION }),
  dynamoClient: new DynamoDBClient({ region: AWS_REGION }),
  projectTag: PROJECT_TAG,
  interactionTable: INTERACTION_TABLE,
});
const commands = createCommandHandlers(services);

export const handler = createInteractionHandler({
  publicKey: DISCORD_PUBLIC_KEY,
  allowedGuildId: ALLOWED_GUILD_ID,
  verifyRequest: verifyKey,
  recordInteraction: services.recordInteraction,
  handleAutocomplete: commands.handleAutocomplete,
  handleCommand: commands.handleCommand,
});

export { hasFreshTimestamp } from "./discord";
export {
  describeServer,
  formatUptime,
  portFromTag,
  probeMinecraft,
  resolveServer,
} from "./minecraft";
export { recordOnce } from "./services";
export type { MinecraftServer } from "./minecraft";
