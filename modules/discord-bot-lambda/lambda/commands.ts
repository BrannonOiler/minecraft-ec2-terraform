import type { APIGatewayProxyResult } from "aws-lambda";
import {
  autocompleteResponse,
  DiscordCommandData,
  findOption,
  response,
} from "./discord";
import {
  describeServerHealth,
  MinecraftServer,
  resolveServer,
} from "./minecraft";

export type CommandDependencies = {
  listServers: () => Promise<MinecraftServer[]>;
  startServer: (server: MinecraftServer) => Promise<void>;
  stopServerGracefully: (server: MinecraftServer) => Promise<void>;
  describeHealth?: (server: MinecraftServer) => Promise<string>;
};

export const createCommandHandlers = (dependencies: CommandDependencies) => {
  const handleAutocomplete = async (
    data: DiscordCommandData,
  ): Promise<APIGatewayProxyResult> => {
    const query = String(
      findOption(data.options, (option) => option.focused === true)?.value ?? "",
    ).toLowerCase();
    const choices = (await dependencies.listServers())
      .filter(
        (server) =>
          server.key.toLowerCase().includes(query) ||
          server.name.toLowerCase().includes(query),
      )
      .slice(0, 25)
      .map((server) => ({
        name: server.publicIp
          ? `${server.name} — ${server.publicIp}:${server.port}`
          : server.name,
        value: server.key,
      }));

    return autocompleteResponse(choices);
  };

  const handleCommand = async (
    data: DiscordCommandData,
  ): Promise<APIGatewayProxyResult> => {
    const action = data.name;
    const selected = findOption(
      data.options,
      (option) => option.name === "server",
    );
    const servers = await dependencies.listServers();

    if (action === "status") {
      const describeHealth = dependencies.describeHealth ?? describeServerHealth;
      return servers.length === 0
        ? response("No managed Minecraft servers were found.")
        : response(
            (await Promise.all(
              servers.map((server) => describeHealth(server)),
            )).join("\n"),
          );
    }
    if (!action || !["start", "stop", "status"].includes(action)) {
      return response(`Unknown command: ${action ?? "missing"}`);
    }

    if (!selected?.value) {
      return response("Choose a server from the search results.");
    }
    const server = resolveServer(servers, String(selected.value));

    if (action === "start") {
      if (["running", "pending"].includes(server.state)) {
        return response(`⚠️ **${server.name}** is already ${server.state}.`);
      }
      if (["stopping", "shutting-down"].includes(server.state)) {
        return response(
          `⚠️ **${server.name}** is ${server.state}; wait before starting it.`,
        );
      }
      await dependencies.startServer(server);
      const address = server.publicIp
        ? `${server.publicIp}:${server.port}`
        : "static IP unavailable";
      return response(
        `✅ **${server.name}** is starting. Connect at **${address}**.`,
      );
    }

    if (["stopped", "stopping", "shutting-down"].includes(server.state)) {
      return response(`⚠️ **${server.name}** is already ${server.state}.`);
    }
    if (server.state === "pending") {
      return response(
        `⚠️ **${server.name}** is pending; wait before stopping it.`,
      );
    }
    await dependencies.stopServerGracefully(server);
    return response(`🛑 **${server.name}** is stopping gracefully…`);
  };

  return { handleAutocomplete, handleCommand };
};
