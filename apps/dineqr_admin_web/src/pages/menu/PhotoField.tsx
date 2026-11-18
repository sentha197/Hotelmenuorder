import { Camera, Check, ImagePlus, Images, Trash2, Upload } from 'lucide-react';
import { AnimatePresence, motion } from 'motion/react';
import { useRef, useState } from 'react';
import { Button } from '@/components/ui/Button';
import { cn } from '@/components/ui/cn';
import { Spinner } from '@/components/ui/Feedback';
import { imageUrl } from '@/config/env';
import { bundledImages, isNetworkImage } from '@/core/menu';
import { errorMessage } from '@/state/run';

/** The bundled sample photos as a grid (PhotoPicker). */
export function PhotoPicker({ selected, onSelect, allowNone = true }: { selected: string; onSelect: (path: string) => void; allowNone?: boolean }) {
  return (
    <div className="grid grid-cols-[repeat(auto-fill,minmax(72px,1fr))] gap-2">
      {allowNone && (
        <button
          type="button"
          onClick={() => onSelect('')}
          aria-pressed={selected === ''}
          className={cn('grid aspect-square place-items-center rounded-xl border text-[11px] font-semibold', selected === '' ? 'border-brand-text text-brand-text' : 'border-line text-faint hover:border-line-strong')}
        >
          No photo
        </button>
      )}
      {bundledImages.map((path) => {
        const on = path === selected;
        return (
          <button key={path} type="button" onClick={() => onSelect(path)} aria-pressed={on} aria-label={path.split('/').pop()?.replace('.jpg', '').replaceAll('_', ' ')} className={cn('relative aspect-square overflow-hidden rounded-xl border-2', on ? 'border-brand-text' : 'border-transparent')}>
            <img src={imageUrl(path)} alt="" loading="lazy" className="h-full w-full object-cover" />
            {on && (
              <span className="absolute inset-0 grid place-items-center bg-black/35">
                <Check size={20} className="text-white" aria-hidden />
              </span>
            )}
          </button>
        );
      })}
    </div>
  );
}

const isTouch = () => typeof window !== 'undefined' && window.matchMedia?.('(pointer: coarse)').matches;

/**
 * A dish or offer photo: upload one (or take one on a phone or tablet), or
 * use a bundled sample (DishPhotoField). An uploaded photo and a sample are
 * labelled differently so a sample is never mistaken for the restaurant's own.
 */
export function PhotoField({ image, onChange, upload, failMessage = 'The photo could not be uploaded. Please try again.' }: { image: string; onChange: (url: string) => void; upload: (bytes: Uint8Array) => Promise<string>; failMessage?: string }) {
  const file = useRef<HTMLInputElement>(null);
  const camera = useRef<HTMLInputElement>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [samples, setSamples] = useState(false);
  const uploaded = isNetworkImage(image);

  const pick = async (list: FileList | null) => {
    const chosen = list?.[0];
    if (!chosen) return;
    setBusy(true);
    setError(null);
    try {
      const bytes = new Uint8Array(await chosen.arrayBuffer());
      onChange(await upload(bytes));
    } catch (e) {
      const message = errorMessage(e);
      setError(message === 'Something went wrong. Please try again.' ? failMessage : message);
    } finally {
      setBusy(false);
      if (file.current) file.current.value = '';
      if (camera.current) camera.current.value = '';
    }
  };

  return (
    <div className="flex flex-col gap-3">
      <div className="relative aspect-[16/9] w-full max-w-md overflow-hidden rounded-2xl border border-line bg-panel-2">
        {image ? (
          <img src={imageUrl(image)} alt="" className="h-full w-full object-cover" />
        ) : (
          <div className="grid h-full w-full place-items-center text-center text-faint">
            <div>
              <ImagePlus size={30} className="mx-auto" aria-hidden />
              <p className="mt-2 text-[13px] font-semibold">No photo yet</p>
            </div>
          </div>
        )}
        {image && <span className="absolute left-3 top-3 rounded-full bg-black/60 px-2.5 py-1 text-[11px] font-semibold text-white backdrop-blur">{uploaded ? 'Your photo' : 'Sample photo'}</span>}
        <AnimatePresence>
          {busy && (
            <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="absolute inset-0 grid place-items-center bg-black/45 backdrop-blur-sm">
              <Spinner size={28} className="text-white" />
            </motion.div>
          )}
        </AnimatePresence>
      </div>
      <input ref={file} type="file" accept="image/*" className="sr-only" tabIndex={-1} onChange={(e) => void pick(e.target.files)} aria-hidden />
      <input ref={camera} type="file" accept="image/*" capture="environment" className="sr-only" tabIndex={-1} onChange={(e) => void pick(e.target.files)} aria-hidden />
      <div className="flex flex-wrap gap-2">
        <Button size="sm" icon={Upload} disabled={busy} onClick={() => file.current?.click()}>
          {image ? 'Replace' : 'Upload photo'}
        </Button>
        {isTouch() && (
          <Button size="sm" icon={Camera} disabled={busy} onClick={() => camera.current?.click()}>
            Camera
          </Button>
        )}
        <Button size="sm" variant="ghost" icon={Images} onClick={() => setSamples((s) => !s)}>
          {samples ? 'Hide samples' : 'Use a sample'}
        </Button>
        {image && (
          <Button size="sm" variant="ghost" icon={Trash2} disabled={busy} onClick={() => onChange('')}>
            Remove
          </Button>
        )}
      </div>
      {error && (
        <p role="alert" className="text-[12.5px] text-danger">
          {error}
        </p>
      )}
      <AnimatePresence initial={false}>
        {samples && (
          <motion.div initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: 'auto' }} exit={{ opacity: 0, height: 0 }} className="overflow-hidden">
            <p className="mb-2 text-[12px] text-faint">Sample photos ship with the app. They are useful while setting up, but replace them with your own before going live.</p>
            <PhotoPicker selected={image} onSelect={onChange} allowNone={false} />
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
