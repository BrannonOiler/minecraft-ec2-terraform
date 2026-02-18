import type { Options } from "tsup";

export const tsup: Options = {
  entryPoints: ["index.ts"],
  format: "cjs",
  bundle: true,
  splitting: false,
  clean: true,
  outDir: "dist",
  minify: true,
  noExternal: ["@aws-sdk/client-ec2", "discord-interactions"],
};
