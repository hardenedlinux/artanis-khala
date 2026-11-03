import { useEffect, useState } from "react";
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

  useEffect(() => {
    const cleanups = Object.keys(statuses).map((id) => downloadEvents(id, (status) => {
      setStatuses((current) => ({ ...current, [id]: status }));
      if (status.state === "done") void refetch();
    }));
    return () => cleanups.forEach((cleanup) => cleanup());
  }, [Object.keys(statuses).join("|"), refetch]);

  async function install(name: string) {
    const status = await api.startDownload(name);
    setStatuses((current) => ({ ...current, [status.id]: status }));
  }
  return <Card><CardHeader><CardTitle>{t("models.catalog")}</CardTitle></CardHeader><CardContent>
    <Table><TableHeader><TableRow><TableHead>{t("models.name")}</TableHead><TableHead>{t("models.size")}</TableHead><TableHead>{t("models.status")}</TableHead></TableRow></TableHeader>
      <TableBody>{data.map((item) => {
        const status = statuses[item.name];
        const percent = status?.bytes_total ? (status.bytes_done / status.bytes_total) * 100 : 0;
        return <TableRow key={item.name}><TableCell>{item.name}</TableCell><TableCell>{Math.round(item.size / 1024 / 1024)} MiB</TableCell>
          <TableCell className="space-x-2"><span>{status?.state ?? (item.installed ? t("common.installed") : "")}</span>
            {status && !["done", "failed", "cancelled"].includes(status.state) && <><Progress className="inline-block w-24" value={percent} /><Button size="sm" variant="outline" onClick={() => api.cancelDownload(status.id)}>{t("models.cancel")}</Button></>}
            {!item.installed && !status && <Button size="sm" onClick={() => install(item.name)}>{t("common.install")}</Button>}
          </TableCell></TableRow>;
      })}</TableBody></Table>
  </CardContent></Card>;
}
