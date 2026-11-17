/**
 * MCP tool surface — deliberately small. The AI speaks semantics only:
 * archetypes and content, never coordinates. Tools map 1:1 onto engine
 * command ops; the Deck DO owns state and versioning.
 */

export interface ToolDef {
  name: string;
  description: string;
  inputSchema: {
    type: "object";
    properties: Record<string, unknown>;
    required?: string[];
  };
}

const deckRef = {
  type: "object",
  description: "The current deck state, as returned by create_deck / get_deck. Pass it back unchanged.",
};

const arch = { type: "string", enum: ["cover", "agenda", "section", "statement", "stat_wall", "split", "comparison", "chart_hero", "closing"] };

export const TOOLS: ToolDef[] = [
  {
    name: "deck_meta",
    description: "List available slide archetypes and deck design families (DNAs). Call this first when planning a deck.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "create_deck",
    description: "Create a new presentation. Returns the deck state you pass into every other tool.",
    inputSchema: {
      type: "object",
      properties: {
        title: { type: "string" },
        family: { type: "string", enum: ["swiss_editorial", "cinematic", "magazine_serif"], description: "Design family. Default swiss_editorial." },
      },
      required: ["title"],
    },
  },
  {
    name: "get_deck",
    description: "Fetch the current deck state.",
    inputSchema: { type: "object", properties: { deck: deckRef }, required: ["deck"] },
  },
  {
    name: "add_slide",
    description: "Append a slide with semantic content. The layout engine places everything. Use varied archetypes; the pacing governor flags repetition.",
    inputSchema: {
      type: "object",
      properties: {
        deck: deckRef,
        archetype: arch,
        content: { type: "object", description: "Archetype-specific content: e.g. stat_wall wants {kind:'stat_wall', title, stats:[{value,label}]}." },
      },
      required: ["deck", "archetype"],
    },
  },
  {
    name: "update_slide",
    description: "Replace one slide's content (or archetype).",
    inputSchema: {
      type: "object",
      properties: { deck: deckRef, slide_id: { type: "string" }, archetype: arch, content: { type: "object" } },
      required: ["deck", "slide_id", "archetype", "content"],
    },
  },
  {
    name: "delete_slide",
    description: "Remove a slide by id.",
    inputSchema: { type: "object", properties: { deck: deckRef, slide_id: { type: "string" } }, required: ["deck", "slide_id"] },
  },
  {
    name: "move_slide",
    description: "Reorder a slide to a new index.",
    inputSchema: {
      type: "object",
      properties: { deck: deckRef, slide_id: { type: "string" }, to_index: { type: "number" } },
      required: ["deck", "slide_id", "to_index"],
    },
  },
  {
    name: "deck_pacing",
    description: "Audit deck rhythm (repetition, density runs, missing agenda) and get the suggested next archetype.",
    inputSchema: { type: "object", properties: { deck: deckRef }, required: ["deck"] },
  },
  {
    name: "deck_status",
    description: "Live status: version, slide count, connected editor sessions.",
    inputSchema: { type: "object", properties: { deck: deckRef }, required: ["deck"] },
  },
];

export const TOOL_NAMES = new Set(TOOLS.map((t) => t.name));

/** Convert an MCP tool call into an engine command op. */
export function toolToCommand(name: string, args: Record<string, unknown>): Record<string, unknown> | null {
  const d = (args.deck ?? undefined) as Record<string, unknown> | undefined;
  switch (name) {
    case "deck_meta":
      return { op: "meta" };
    case "create_deck":
      return { op: "new_deck", title: args.title, family: args.family ?? "swiss_editorial" };
    case "get_deck":
      return { op: "pacing", deck: d }; // pacing returns issues + next; deck passes through
    case "add_slide":
      return { op: "add_slide", deck: d, archetype: args.archetype, content: args.content };
    case "update_slide":
      return { op: "update_slide", deck: d, slide_id: args.slide_id, archetype: args.archetype, content: args.content };
    case "delete_slide":
      return { op: "delete_slide", deck: d, slide_id: args.slide_id };
    case "move_slide":
      return { op: "move_slide", deck: d, slide_id: args.slide_id, to_index: args.to_index };
    case "deck_pacing":
      return { op: "pacing", deck: d };
    default:
      return null;
  }
}
