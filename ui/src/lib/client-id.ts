let sequence = 0;

export function newClientId(): string {
  sequence += 1;
  return [
    "khala",
    Date.now().toString(36),
    sequence.toString(36),
    Math.random().toString(36).slice(2, 10),
  ].join("-");
}
