import { useQuery } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { api, viewUrl } from "@/lib/api";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import type { ComfyNode } from "@/lib/api";

export function HistoryPage() {
  const { t } = useTranslation();
  const { data = {} } = useQuery({ queryKey: ["history"], queryFn: api.history });
  const entries = Object.entries(data);
  if (!entries.length) return <p>{t("history.empty")}</p>;
  async function rerun(id: string, prompt: Record<string, ComfyNode>) {
    await api.queuePrompt(prompt, `history-${id}`);
  }
  return <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">{entries.map(([id, entry]) => {
    const image = Object.values(entry.outputs ?? {}).flatMap((item) => item.images ?? [])[0];
    return <Card key={id}><CardContent className="space-y-3 pt-6">
      {image && <img src={viewUrl(image)} alt={id} className="w-full rounded-md" />}
      {entry.prompt && <details><summary>{t("history.parameters")}</summary><pre className="overflow-auto text-xs">{JSON.stringify(entry.prompt[2], null, 2)}</pre></details>}
      {entry.prompt && <Button variant="outline" onClick={() => rerun(id, entry.prompt![2])}>{t("common.reRun")}</Button>}
    </CardContent></Card>;
  })}</div>;
}
