import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { api, type KhalaSettings } from "@/lib/api";
import { languages, setLanguage, type Language } from "@/i18n";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

export function SettingsPage() {
  const { t, i18n } = useTranslation();
  const { data } = useQuery({ queryKey: ["settings"], queryFn: api.settings });
  const [settings, setSettings] = useState<KhalaSettings>({ mirror: "auto", download_threads: 4 });
  useEffect(() => { if (data) setSettings(data); }, [data]);
  return <Card><CardHeader><CardTitle>{t("settings.title")}</CardTitle></CardHeader><CardContent className="space-y-4">
    <label className="block">{t("settings.language")}<Select value={i18n.language} onValueChange={(value) => void setLanguage(value as Language)}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent>{languages.map((language) => <SelectItem key={language} value={language}>{language}</SelectItem>)}</SelectContent></Select></label>
    <label className="block">{t("settings.mirror")}<Select value={settings.mirror} onValueChange={(mirror) => setSettings({ ...settings, mirror })}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent>{["auto", "huggingface", "hf-mirror", "modelscope"].map((mirror) => <SelectItem key={mirror} value={mirror}>{mirror}</SelectItem>)}</SelectContent></Select></label>
    <label className="block">{t("settings.downloadThreads")}<Input type="number" value={settings.download_threads} onChange={(event) => setSettings({ ...settings, download_threads: Number(event.target.value) })} /></label>
    <Button onClick={() => void api.saveSettings(settings)}>{t("common.save")}</Button>
    <a className="block underline" href="/">{t("settings.nodeEditor")}</a>
  </CardContent></Card>;
}
