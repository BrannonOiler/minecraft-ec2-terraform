import type { APIGatewayProxyEvent, APIGatewayProxyResult } from "aws-lambda";
import {
  InteractionResponseType,
  InteractionType,
} from "discord-interactions";

const MAX_INTERACTION_AGE_SECONDS = 300;

export type DiscordOption = {
  name?: string;
  type?: number;
  value?: string;
  focused?: boolean;
  options?: DiscordOption[];
};

export type DiscordCommandData = {
  name?: string;
  options?: DiscordOption[];
};

type DiscordInteraction = {
  id?: string;
  type?: number;
  guild_id?: string;
  member?: { user?: { id?: string } };
  user?: { id?: string };
  data?: DiscordCommandData;
};

export const response = (content: string): APIGatewayProxyResult => ({
  statusCode: 200,
  body: JSON.stringify({
    type: InteractionResponseType.CHANNEL_MESSAGE_WITH_SOURCE,
    data: { content },
  }),
});

export const autocompleteResponse = (
  choices: Array<{ name: string; value: string }>,
): APIGatewayProxyResult => ({
  statusCode: 200,
  body: JSON.stringify({
    type: InteractionResponseType.APPLICATION_COMMAND_AUTOCOMPLETE_RESULT,
    data: { choices },
  }),
});

export const findOption = (
  options: DiscordOption[] | undefined,
  predicate: (option: DiscordOption) => boolean,
): DiscordOption | undefined => {
  for (const option of options ?? []) {
    if (predicate(option)) return option;
    const nested = findOption(option.options, predicate);
    if (nested) return nested;
  }
  return undefined;
};

export const hasFreshTimestamp = (
  timestamp: string,
  nowMs = Date.now(),
): boolean => {
  const seconds = Number(timestamp);
  return Number.isFinite(seconds) &&
    Math.abs(Math.floor(nowMs / 1000) - seconds) <= MAX_INTERACTION_AGE_SECONDS;
};

export type InteractionHandlerDependencies = {
  publicKey?: string;
  allowedGuildId?: string;
  verifyRequest: (
    body: string,
    signature: string,
    timestamp: string,
    publicKey: string,
  ) => Promise<boolean> | boolean;
  recordInteraction: (interactionId: string) => Promise<boolean>;
  handleAutocomplete: (
    data: DiscordCommandData,
  ) => Promise<APIGatewayProxyResult>;
  handleCommand: (data: DiscordCommandData) => Promise<APIGatewayProxyResult>;
};

export const createInteractionHandler = (
  dependencies: InteractionHandlerDependencies,
) => async (event: APIGatewayProxyEvent): Promise<APIGatewayProxyResult> => {
  if (!dependencies.publicKey) {
    return { statusCode: 500, body: "Missing Discord public key" };
  }

  const signature = event.headers["x-signature-ed25519"] ?? "";
  const timestamp = event.headers["x-signature-timestamp"] ?? "";
  const body = event.body ?? "";
  if (
    !hasFreshTimestamp(timestamp) ||
    !await dependencies.verifyRequest(
      body,
      signature,
      timestamp,
      dependencies.publicKey,
    )
  ) {
    return { statusCode: 401, body: "Invalid or expired request signature" };
  }

  const interaction = JSON.parse(body) as DiscordInteraction;
  if (interaction.type === InteractionType.PING) {
    return {
      statusCode: 200,
      body: JSON.stringify({ type: InteractionResponseType.PONG }),
    };
  }
  if (
    dependencies.allowedGuildId &&
    interaction.guild_id !== dependencies.allowedGuildId
  ) {
    return response("This bot is not enabled in this Discord server.");
  }

  try {
    if (interaction.type === InteractionType.APPLICATION_COMMAND_AUTOCOMPLETE) {
      return await dependencies.handleAutocomplete(interaction.data ?? {});
    }
    if (interaction.type !== InteractionType.APPLICATION_COMMAND) {
      return response("Unsupported interaction type.");
    }
    if (
      !interaction.id ||
      !await dependencies.recordInteraction(interaction.id)
    ) {
      return response("This interaction was already processed.");
    }

    console.log(JSON.stringify({
      interactionId: interaction.id,
      guildId: interaction.guild_id,
      userId: interaction.member?.user?.id ?? interaction.user?.id,
      command: interaction.data?.name,
    }));
    return await dependencies.handleCommand(interaction.data ?? {});
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    console.error("Error handling Discord interaction", error);
    return response(`❌ ${message}`);
  }
};
