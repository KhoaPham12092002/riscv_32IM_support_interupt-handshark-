#!/usr/bin/env node
/**
 * Gemini Worker MCP Server
 * Cho phép Claude Code gọi Gemini CLI như một native tool.
 *
 * Tools:
 *   gemini_edit   — Gemini chỉnh sửa file (auto_edit mode)
 *   gemini_task   — Gemini thực thi task phức tạp (yolo mode)
 *   gemini_review — Gemini đọc và review, không ghi file (plan mode)
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { spawnSync } from "child_process";
import { existsSync } from "fs";
import { resolve } from "path";

const GEMINI_BIN = "/home/key/.npm-global/bin/gemini";
const HOME = "/home/key";
const TIMEOUT_MS = 120_000;

function runGemini(prompt, mode) {
  const result = spawnSync(
    GEMINI_BIN,
    ["--prompt", prompt, "--approval-mode", mode, "--output-format", "text"],
    {
      cwd: HOME,
      timeout: TIMEOUT_MS,
      encoding: "utf-8",
      env: { ...process.env, HOME },
    }
  );

  if (result.error) {
    throw new Error(`Gemini process error: ${result.error.message}`);
  }

  const output = (result.stdout || "").trim();
  const stderr = (result.stderr || "").trim();

  if (result.status !== 0) {
    throw new Error(`Gemini exit ${result.status}: ${stderr || output}`);
  }

  return output || stderr;
}

function buildPrompt(instruction, files) {
  if (!files || files.length === 0) return instruction;

  const resolvedFiles = files
    .map((f) => resolve(HOME, f))
    .filter((f) => {
      if (!f.startsWith(HOME)) {
        process.stderr.write(`[gemini-mcp] Skipping out-of-workspace file: ${f}\n`);
        return false;
      }
      if (!existsSync(f)) {
        process.stderr.write(`[gemini-mcp] Warning: file not found: ${f}\n`);
      }
      return true;
    });

  if (resolvedFiles.length === 0) return instruction;

  return `${instruction}\n\nFiles:\n${resolvedFiles.map((f) => `- ${f}`).join("\n")}`;
}

// ── Server setup ─────────────────────────────────────────────────────────────

const server = new McpServer({
  name: "gemini-worker",
  version: "1.0.0",
});

// ── Tool: gemini_edit ─────────────────────────────────────────────────────────

server.tool(
  "gemini_edit",
  "Delegate a file editing task to Gemini 2.5 Pro. Gemini will read the specified files and apply the requested changes automatically. Files must be inside /home/key/.",
  {
    instruction: z.string().describe("Clear instruction of what to edit/change"),
    files: z
      .array(z.string())
      .optional()
      .describe("List of file paths (absolute or relative to /home/key)"),
  },
  async ({ instruction, files }) => {
    const prompt = buildPrompt(instruction, files);
    const output = runGemini(prompt, "auto_edit");
    return { content: [{ type: "text", text: output }] };
  }
);

// ── Tool: gemini_task ─────────────────────────────────────────────────────────

server.tool(
  "gemini_task",
  "Delegate a complex task to Gemini 2.5 Pro with full autonomy (can run shell commands, install packages, create/edit files). Use for tasks like: scaffold a project, run tests and fix failures, install deps. Files must be inside /home/key/.",
  {
    instruction: z.string().describe("Detailed task description"),
    files: z
      .array(z.string())
      .optional()
      .describe("Relevant files or directories for context"),
  },
  async ({ instruction, files }) => {
    const prompt = buildPrompt(instruction, files);
    const output = runGemini(prompt, "yolo");
    return { content: [{ type: "text", text: output }] };
  }
);

// ── Tool: gemini_review ───────────────────────────────────────────────────────

server.tool(
  "gemini_review",
  "Ask Gemini 2.5 Pro to review code or analyze files without making any changes. Good for getting a second opinion, listing issues, or summarizing a codebase section.",
  {
    instruction: z.string().describe("What to review or analyze"),
    files: z
      .array(z.string())
      .optional()
      .describe("Files to review"),
  },
  async ({ instruction, files }) => {
    const prompt = buildPrompt(instruction, files);
    const output = runGemini(prompt, "plan");
    return { content: [{ type: "text", text: output }] };
  }
);

// ── Start ─────────────────────────────────────────────────────────────────────

const transport = new StdioServerTransport();
await server.connect(transport);
process.stderr.write("[gemini-mcp] Gemini Worker MCP server started\n");
