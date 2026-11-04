import { useEffect, useRef, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { api, downloadEvents, type DownloadStatus } from "@/lib/api";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Progress } from "@/components/ui/progress";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";

export function ModelsPage() {
  const { t } = useTranslation();
  const { data = [], refetch } = useQuery({ queryKey: ["catalog"], queryFn: api.catalog });
  const [statuses, setStatuses] = useState<Record<string, DownloadStatus>>({});
  const cancelled = useRef(new Set<string>());

  useEffect(() => {
    const cleanups = Object.keys(statuses).map((id) => downloadEvents(id, (status) => {
      const next = cancelled.current.has(id) ? { ...status, state: "cancelled" as const } : status;
      setStatuses((current) => ({ ...current, [id]: next }));
      if (status.state === "done") void refetch();
    }));
    return () => cleanups.forEach((cleanup) => cleanup());
  }, [Object.keys(statuses).join("|"), refetch]);

  async function install(name: string) {
    setStatuses((current) => ({
      ...current,
      [name]: {
        id: name,
        state: "downloading",
        bytes_done: 0,
        bytes_total: data.find((item) => item.name === name)?.size ?? 0,
        speed: 0,
        source: null,
        error: null,
        verified: false,
      },
    }));
    const status = await api.startDownload(name);
    setStatuses((current) => ({ ...current, [status.id]: status }));
    void (async () => {
      let current = status;
      while (!["done", "failed", "cancelled"].includes(current.state)) {
        await new Promise((resolve) => window.setTimeout(resolve, 500));
        if (cancelled.current.has(name)) {
          current = { ...current, state: "cancelled" };
          setStatuses((state) => ({ ...state, [name]: current }));
          break;
        }
        const downloads = await api.downloads();
        current = downloads.find((entry) => entry.id === name) ?? current;
        setStatuses((state) => ({ ...state, [name]: current }));
      }
      if (current.state === "done") await refetch();
    })();
  }
  function cancel(id: string) {
    cancelled.current.add(id);
    setStatuses((current) => ({
      ...current,
      [id]: { ...current[id], state: "cancelled" },
    }));
    void api.cancelDownload(id);
  }
  return <Card><CardHeader><CardTitle>{t("models.catalog")}</CardTitle></CardHeader><CardContent>
    <Table><TableHeader><TableRow><TableHead>{t("models.name")}</TableHead><TableHead>{t("models.size")}</TableHead><TableHead>{t("models.status")}</TableHead></TableRow></TableHeader>
      <TableBody>{data.map((item) => {
        const status = statuses[item.name];
        const percent = status?.bytes_total ? (status.bytes_done / status.bytes_total) * 100 : 0;
        const active = status && ["queued", "probing", "downloading", "verifying"].includes(status.state);
        const label = active ? "downloading"
          : status?.state === "done" ? t("common.installed")
            : status?.state ?? (item.installed ? t("common.installed") : "");
        return <TableRow key={item.name}><TableCell>{item.name}</TableCell><TableCell>{Math.round(item.size / 1024 / 1024)} MiB</TableCell>
          <TableCell className="space-x-2"><span>{label}</span>
            {status && !["done", "failed", "cancelled"].includes(status.state) && <><Progress className="inline-block w-24" value={percent} /><Button size="sm" variant="outline" onClick={() => cancel(status.id)}>{t("models.cancel")}</Button></>}
            {!item.installed && !status && <Button size="sm" onClick={() => install(item.name)}>{t("common.install")}</Button>}
          </TableCell></TableRow>;
      })}</TableBody></Table>
  </CardContent></Card>;
}
