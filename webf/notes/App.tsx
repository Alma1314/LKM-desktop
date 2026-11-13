import { useEffect, useRef, useState } from 'react';
import { miniApp, type MiniAppContext } from '../sdk';

interface Note { id: string; text: string; updatedAt: string }

function labels(locale: string) {
  const tw = /tw|hk|hant/i.test(locale);
  return locale.startsWith('en') ? {
    title: 'Notes', hint: 'A quiet place for your thoughts. Saved on this device.',
    save: 'Save note', cancel: 'Cancel', edit: 'Edit', remove: 'Delete',
    empty: 'No notes yet. Write your first one above.', placeholder: 'What’s on your mind?',
    failure: 'Could not load or save. Retry before leaving.', retry: 'Retry',
    confirm: 'Delete this note?', loading: 'Loading…',
  } : {
    title: tw ? '便箋' : '便签', hint: tw ? '記下此刻的想法，儲存於本機。' : '记下此刻的想法，保存在本机。',
    save: tw ? '儲存便箋' : '保存便签', cancel: '取消', edit: tw ? '編輯' : '编辑', remove: tw ? '刪除' : '删除',
    empty: tw ? '還沒有便箋，在上方寫下第一條吧。' : '还没有便签，在上方写下第一条吧。', placeholder: tw ? '此刻在想什麼？' : '此刻在想什么？',
    failure: tw ? '讀取或儲存失敗，請在離開前重試。' : '读取或保存失败，请在离开前重试。', retry: tw ? '重試' : '重试',
    confirm: tw ? '刪除這條便箋？' : '删除这条便签？', loading: tw ? '載入中…' : '加载中…',
  };
}

export default function App() {
  const [notes, setNotes] = useState<Note[]>([]);
  const [text, setText] = useState('');
  const [editing, setEditing] = useState('');
  const [deleting, setDeleting] = useState('');
  const [context, setContext] = useState<MiniAppContext | null>(null);
  const [ready, setReady] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(false);
  const saving = useRef(false);
  const t = labels(context?.locale ?? 'zh-CN');

  async function boot() {
    setError(false);
    try {
      setContext(await miniApp.context());
      setNotes(await miniApp.load<Note[]>() ?? []);
      setReady(true);
    } catch { setError(true); }
  }

  useEffect(() => { void boot(); }, []);

  function cancel() { setText(''); setEditing(''); }

  async function commit(id?: string) {
    if (saving.current || (!id && !text.trim())) return;
    saving.current = true;
    setBusy(true);
    setError(false);
    try {
      let next: Note[];
      if (id) next = notes.filter(note => note.id !== id);
      else {
        const note = { id: editing || await miniApp.newId(), text: text.trim(), updatedAt: new Date().toISOString() };
        next = [note, ...notes.filter(item => item.id !== note.id)];
      }
      await miniApp.save(next);
      setNotes(next);
      if (!id || editing === id) cancel();
      setDeleting('');
    } catch { setError(true); }
    finally { saving.current = false; setBusy(false); }
  }

  return <div className={`app${context?.dark ? ' dark' : ''}`}><div className="page">
    <h1>{t.title}</h1><p className="muted">{t.hint}</p>
    {error && <p className="error" role="alert">{t.failure}</p>}
    {!ready ? <div className="card"><p>{t.loading}</p>
      {error && <button onClick={() => void boot()}>{t.retry}</button>}
    </div> : <>
      <div className="card">
        <textarea value={text} placeholder={t.placeholder} aria-label={t.placeholder} disabled={busy}
          onInput={event => setText(event.currentTarget.value)} />
        <div className="row"><button className="primary" disabled={busy || !text.trim()} onClick={() => void commit()}>{t.save}</button>
          {editing && <button disabled={busy} onClick={cancel}>{t.cancel}</button>}</div>
      </div>
      {!notes.length && <p className="muted">{t.empty}</p>}
      {notes.map(note => <div key={note.id} className="card">
        <p className="text">{note.text}</p>
        <p className="muted">{new Date(note.updatedAt).toLocaleString()}</p>
        <div className="row"><button disabled={busy} onClick={() => { setEditing(note.id); setText(note.text); }}>{t.edit}</button>
          <button disabled={busy} onClick={() => setDeleting(note.id)}>{t.remove}</button></div>
        {deleting === note.id && <div><p>{t.confirm}</p><div className="row">
          <button disabled={busy} onClick={() => void commit(note.id)}>{t.remove}</button>
          <button disabled={busy} onClick={() => setDeleting('')}>{t.cancel}</button></div></div>}
      </div>)}
    </>}
  </div></div>;
}
