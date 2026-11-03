import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
import { api, streamChat, type ChatMessage } from "@/lib/api";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";

export function ChatPage() {
  const { t } = useTranslation();
  const { data } = useQuery({ queryKey: ["models"], queryFn: api.models });
  const models = data?.models ?? [];
  const [model, setModel] = useState("");
  const [text, setText] = useState("");
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  async function send() {
    if (!model || !text) return;
    const next: ChatMessage[] = [...messages, { role: "user", content: text }];
    setMessages([...next, { role: "assistant", content: "" }]);
    setText("");
    await streamChat(model, next, (token) => setMessages((current) => {
      const copy = [...current];
      copy[copy.length - 1] = { role: "assistant", content: copy[copy.length - 1].content + token };
      return copy;
    }));
  }
  return <Card><CardContent className="space-y-4 pt-6">
    <Select value={model} onValueChange={setModel}><SelectTrigger><SelectValue placeholder={t("chat.model")} /></SelectTrigger><SelectContent>{models.map((item) => <SelectItem key={item.name} value={item.name}>{item.name}</SelectItem>)}</SelectContent></Select>
    <div className="space-y-2">{messages.length ? messages.map((message, index) => <p key={index}><strong>{message.role}: </strong>{message.content}</p>) : t("chat.empty")}</div>
    <Textarea value={text} onChange={(event) => setText(event.target.value)} placeholder={t("chat.messagePlaceholder")} />
    <Button onClick={send}>{t("chat.send")}</Button>
  </CardContent></Card>;
}
