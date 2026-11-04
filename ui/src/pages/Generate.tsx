import { useEffect, useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { api, type ComfyNodeInfo, type HistoryEntry, viewUrl } from "@/lib/api";
import { buildPrompt } from "@/lib/prompt";
import { initialWsState, previewFromBinary, reduceWsMessage, type WsState } from "@/lib/ws";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Progress } from "@/components/ui/progress";

export function GeneratePage() {
  const { t } = useTranslation();
  const { data: info = {} } = useQuery({ queryKey: ["object-info"], queryFn: api.objectInfo });
  const checkpoints = useMemo(() => {
    const value = (info.CheckpointLoaderSimple as ComfyNodeInfo | undefined)
      ?.input?.required?.ckpt_name?.[0];
    return Array.isArray(value) ? value.map(String) : [];
  }, [info]);
  const [model, setModel] = useState("");
  const [prompt, setPrompt] = useState("");
  const [width, setWidth] = useState(512);
  const [height, setHeight] = useState(512);
  const [steps, setSteps] = useState(20);
  const [seed, setSeed] = useState(1);
  const [enhancedPrompt, setEnhancedPrompt] = useState("");
  const [negative, setNegative] = useState("");
  const [enhancing, setEnhancing] = useState(false);
  const [ws, setWs] = useState<WsState>(initialWsState);
  const [image, setImage] = useState<string | null>(null);
  const [error, setError] = useState("");
  const clientId = useMemo(() => crypto.randomUUID(), []);

  useEffect(() => {
    if (!model) setModel(checkpoints[0] ?? "e2e.safetensors");
  }, [checkpoints, model]);
  useEffect(() => {
    const socket = new WebSocket(`${location.protocol === "https:" ? "wss" : "ws"}://${location.host}/ws?clientId=${clientId}`);
    socket.binaryType = "arraybuffer";
    socket.onmessage = (event) => {
      if (event.data instanceof ArrayBuffer) {
        setWs((current) => ({ ...current, previewUrl: previewFromBinary(event.data) }));
        return;
      }
      const message = JSON.parse(event.data) as { type: string; data: Record<string, unknown> };
      setWs((current) => reduceWsMessage(current, message.type, message.data));
    };
    return () => socket.close();
  }, [clientId]);

  async function generate() {
    setError("");
    try {
      const result = await api.queuePrompt(buildPrompt({
        prompt: enhancedPrompt || prompt, negative, model, width, height, steps, seed,
      }), clientId);
      setWs({ ...initialWsState, promptId: result.prompt_id });
      window.setTimeout(async () => {
        const history = await api.history();
        const entry: HistoryEntry | undefined = history[result.prompt_id];
        const output = Object.values(entry?.outputs ?? {}).flatMap((item) => item.images ?? [])[0];
        if (output) setImage(viewUrl(output));
      }, 1200);
    } catch (cause) {
      setError(t("generate.failed"));
      console.error(cause);
    }
  }

  return (
    <div className="grid gap-6 lg:grid-cols-2">
      <Card><CardHeader><CardTitle>{t("generate.title")}</CardTitle></CardHeader>
        <CardContent className="space-y-4">
          <Select value={model} onValueChange={setModel}><SelectTrigger><SelectValue placeholder={t("generate.model")} /></SelectTrigger>
            <SelectContent>{checkpoints.map((item) => <SelectItem key={item} value={item}>{item}</SelectItem>)}</SelectContent>
          </Select>
          <Textarea value={prompt} onChange={(event) => setPrompt(event.target.value)} placeholder={t("generate.promptPlaceholder")} />
          <Button
            type="button"
            variant="outline"
            disabled={!prompt || enhancing}
            onClick={() => {
              setEnhancing(true);
              void api.enhance(prompt, "").then((value) => {
                setEnhancedPrompt(value.prompt);
                setNegative(value.negative);
              }).finally(() => setEnhancing(false));
            }}
          >
            {t("generate.enhance")}
          </Button>
          <label className="block text-sm">{t("generate.enhancedPrompt")}
            <Textarea value={enhancedPrompt} onChange={(event) => setEnhancedPrompt(event.target.value)} />
          </label>
          <label className="block text-sm">{t("generate.negative")}
            <Textarea value={negative} onChange={(event) => setNegative(event.target.value)} />
          </label>
          <div className="grid grid-cols-2 gap-3">
            <Input type="number" value={width} onChange={(event) => setWidth(Number(event.target.value))} aria-label={t("generate.width")} />
            <Input type="number" value={height} onChange={(event) => setHeight(Number(event.target.value))} aria-label={t("generate.height")} />
            <Input type="number" value={steps} onChange={(event) => setSteps(Number(event.target.value))} aria-label={t("generate.steps")} />
            <Input type="number" value={seed} onChange={(event) => setSeed(Number(event.target.value))} aria-label={t("generate.seed")} />
          </div>
          <Button onClick={generate} disabled={!model || !prompt}>{t("generate.button")}</Button>
          {error && <p className="text-sm text-destructive">{error}</p>}
        </CardContent>
      </Card>
      <Card><CardHeader><CardTitle>{t("generate.result")}</CardTitle></CardHeader>
        <CardContent className="space-y-4">
          {ws.max > 0 && <><Progress value={(ws.progress / ws.max) * 100} /><p>{t("generate.progress", { value: ws.progress, max: ws.max })}</p></>}
          {(image || ws.previewUrl) ? <img className="w-full rounded-md border" src={image ?? ws.previewUrl ?? ""} alt={t("generate.result")} /> :
            <p className="text-muted-foreground">{t("generate.empty")}</p>}
        </CardContent>
      </Card>
    </div>
  );
}
