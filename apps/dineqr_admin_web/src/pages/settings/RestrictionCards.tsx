import { Check, LocateFixed, Map as MapIcon, Plus, RefreshCw, ShieldCheck, ShieldQuestion, TriangleAlert, X } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { Button, IconButton } from '@/components/ui/Button';
import { InfoRow, SectionCard } from '@/components/ui/Card';
import { cn } from '@/components/ui/cn';
import { confirmDialog } from '@/components/ui/Dialog';
import { Spinner } from '@/components/ui/Feedback';
import { SwitchRow, TextField } from '@/components/ui/Form';
import { toast } from '@/components/ui/Toast';
import { googleMapsKey } from '@/config/env';
import { Geofence, type AuthorizedNetwork, type GeofenceSettings, type NetworkCheck } from '@/core/restrictions';
import { AppFormat } from '@/core/time';
import { saveGeofence, saveNetworkAccess } from '@/state/actions';
import { useGeofence, useNetworkAccess } from '@/state/data';
import { errorMessage, useAction } from '@/state/run';

function LoadState({ loading, error, onRetry, fallback }: { loading: boolean; error: unknown; onRetry: () => void; fallback: string }) {
  if (loading) {
    return (
      <div className="grid place-items-center py-8">
        <Spinner size={26} />
      </div>
    );
  }
  const message = errorMessage(error);
  return (
    <div className="flex flex-col items-start gap-2">
      <p className="text-[13px] text-muted">{message === 'Something went wrong. Please try again.' ? fallback : message}</p>
      <Button size="sm" icon={RefreshCw} onClick={onRetry}>
        Try again
      </Button>
    </div>
  );
}

/**
 * Dine-in guests can order only from the restaurant's own internet
 * connection (WifiRestrictionCard). The server decides from the public
 * address a request comes from; saved on its own.
 */
export function WifiRestrictionCard() {
  const query = useNetworkAccess();
  const [enabled, setEnabled] = useState(false);
  const [takeaway, setTakeaway] = useState(false);
  const [ssid, setSsid] = useState('');
  const [networks, setNetworks] = useState<AuthorizedNetwork[]>([]);
  const [value, setValue] = useState('');
  const [label, setLabel] = useState('');
  const { pending, run } = useAction();

  useEffect(() => {
    const s = query.data;
    if (!s) return;
    setEnabled(s.enabled);
    setTakeaway(s.restrictTakeaway);
    setSsid(s.ssid);
    setNetworks(s.networks);
  }, [query.data]);

  const add = (v: string, l: string) => {
    const text = v.trim();
    if (!text || networks.some((n) => n.value === text)) return;
    setNetworks((list) => [...list, { value: text, label: l, resolved: [] }]);
    setValue('');
    setLabel('');
  };

  const save = async () => {
    const you = query.data?.you;
    if (enabled && !query.data?.enabled && you?.matches !== true) {
      // Switching on from elsewhere is allowed (the owner may be at home), but worth a second look.
      const ok = await confirmDialog({
        title: 'Switch the restriction on?',
        message: 'This device is not on one of the listed networks right now, so the server cannot confirm the list is right. Guests not on a listed network will not be able to order at their table.',
        confirmLabel: 'Switch on',
        icon: ShieldQuestion,
      });
      if (!ok) return;
    }
    await run(() => saveNetworkAccess({ enabled, ssid, restrictTakeaway: takeaway, networks }), { success: 'Wi-Fi restriction saved' });
  };

  return (
    <SectionCard title="Dine-in Wi-Fi restriction" subtitle="Guests at a table can order and pay only from the restaurant's own internet connection, recognised by its public address. Mobile data and other Wi-Fi networks are refused by the server.">
      {!query.data ? (
        <LoadState loading={query.isPending} error={query.error} onRetry={() => void query.refetch()} fallback="The Wi-Fi restriction could not be loaded." />
      ) : (
        <div className="flex flex-col gap-4">
          <div className="divide-y divide-line">
            <SwitchRow title="Require the restaurant Wi-Fi" description="Off: guests order from any network, as before." checked={enabled} onChange={setEnabled} />
            <SwitchRow title="Include takeaway orders" description="Off: takeaway guests can order from anywhere." checked={takeaway} onChange={setTakeaway} />
          </div>
          <TextField label="Wi-Fi name shown to guests (optional)" maxLength={32} value={ssid} onChange={(e) => setSsid(e.target.value)} hint="Only a hint for which network to join. It never grants access: any phone can show any name." />
          <div>
            <p className="text-[14px] font-semibold text-ink">Authorised networks</p>
            <p className="text-[12.5px] leading-relaxed text-muted">
              The restaurant connection's public address (IPv4, e.g. 203.0.113.7), its IPv6 prefix (e.g. 2001:db8:12:34::/64), a small range, or a dynamic-DNS name (e.g. cafe.ddns.net) if the provider changes the address. Never shown to guests.
            </p>
            <ul className="mt-3 flex flex-col gap-1.5">
              {networks.length === 0 && <li className="text-[13px] text-faint">None yet.</li>}
              {networks.map((n) => (
                <li key={n.value} className="flex items-center gap-3 rounded-xl border border-line bg-panel-2 px-3 py-2">
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-mono text-[13px] text-ink">{n.value}</p>
                    {(n.label || n.resolved.length > 0 || isHost(n.value)) && (
                      <p className="truncate text-[11.5px] text-faint">
                        {[...(n.label ? [n.label] : []), ...(isHost(n.value) ? [n.resolved.length === 0 ? 'does not resolve right now' : `now ${n.resolved.join(', ')}`] : [])].join(' · ')}
                      </p>
                    )}
                  </div>
                  <IconButton icon={X} size="sm" label={`Remove ${n.value}`} onClick={() => setNetworks((list) => list.filter((x) => x.value !== n.value))} />
                </li>
              ))}
            </ul>
            <div className="mt-3 grid gap-2 sm:grid-cols-[1.4fr_1fr_auto] sm:items-end">
              <TextField label="Address, range or hostname" spellCheck={false} value={value} onChange={(e) => setValue(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && (e.preventDefault(), add(value, label))} />
              <TextField label="Label" value={label} onChange={(e) => setLabel(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && (e.preventDefault(), add(value, label))} />
              <Button icon={Plus} onClick={() => add(value, label)} aria-label="Add network">
                Add
              </Button>
            </div>
          </div>
          {query.data.you && <ThisDevice check={query.data.you} onAdd={add} onCheck={() => void query.refetch()} />}
          <Button variant="primary" icon={Check} loading={pending} onClick={() => void save()} className="self-start">
            Save Wi-Fi restriction
          </Button>
        </div>
      )}
    </SectionCard>
  );
}

/** A hostname rather than an address or range. */
const isHost = (value: string) => !value.includes(':') && /[a-z]/.test(value);

/** What the server sees for this device, to confirm the setup works (_ThisDevice). */
function ThisDevice({ check, onAdd, onCheck }: { check: NetworkCheck; onAdd: (value: string, label: string) => void; onCheck: () => void }) {
  const warnings = [
    ...(check.address == null ? ["The server cannot see this device's address, so the restriction would block every guest. Check Network:ClientIpSource on the server."] : []),
    ...(check.address != null && !check.consistent
      ? [`A proxy header names a different address (${Object.entries(check.headers).map(([k, v]) => `${k}: ${v}`).join('; ')}). The server may be seeing a proxy instead of each guest: do not switch the restriction on until this is fixed (see the README).`]
      : []),
    ...(check.sharedCarrier ? ['This connection uses carrier-grade NAT, shared with other customers of the provider. It cannot identify the restaurant: ask the provider for a public address.'] : []),
    ...(check.isPrivate ? ['This is a private address: fine for a test on the local network, never seen for guests of the deployed server.'] : []),
  ];
  const suggestion = check.suggestedEntry;
  return (
    <div className={cn('rounded-2xl border p-4', check.matches ? 'border-success/30 bg-success/6' : 'border-warning/30 bg-warning/6')}>
      <div className="flex items-center gap-2">
        {check.matches ? <ShieldCheck size={19} className="text-success" aria-hidden /> : <ShieldQuestion size={19} className="text-warning" aria-hidden />}
        <p className="min-w-0 flex-1 truncate text-[14px] font-semibold text-ink">This device: {check.address ?? 'unknown'}</p>
        <Button size="sm" variant="ghost" onClick={onCheck}>
          Check again
        </Button>
      </div>
      <p className="mt-1 text-[12.5px] text-muted">{check.matches ? `On an authorised network (${check.matchedBy}).` : 'Not on an authorised network.'}</p>
      <p className="text-[12.5px] text-muted">Seen by the server from its {check.source}. Check once on the restaurant Wi-Fi and once on mobile data: the two addresses must differ.</p>
      {warnings.map((w) => (
        <p key={w} className="mt-2 flex items-start gap-1.5 text-[12.5px] text-warning">
          <TriangleAlert size={15} className="mt-0.5 shrink-0" aria-hidden />
          {w}
        </p>
      ))}
      {!check.matches && suggestion && !check.sharedCarrier && check.consistent && (
        <Button size="sm" icon={Plus} className="mt-3" onClick={() => onAdd(suggestion, 'Restaurant Wi-Fi')}>
          Add this network ({suggestion})
        </Button>
      )}
    </div>
  );
}

// ------------------------------------------------------------- GPS area

interface GoogleMaps {
  Map: new (el: HTMLElement, options: object) => { addListener: (event: string, cb: (e: { latLng: { lat: () => number; lng: () => number } }) => void) => void; panTo: (p: object) => void; fitBounds: (b: unknown) => void };
  Marker: new (options: object) => { setPosition: (p: object) => void; addListener: (event: string, cb: () => void) => void; getPosition: () => { lat: () => number; lng: () => number } };
  Circle: new (options: object) => { setCenter: (p: object) => void; setRadius: (r: number) => void; getBounds: () => unknown };
}

let mapsLoading: Promise<GoogleMaps | null> | null = null;

/** Loads the Maps JavaScript API once (needs VITE_GOOGLE_MAPS_API_KEY). */
function loadGoogleMaps(): Promise<GoogleMaps | null> {
  if (!googleMapsKey) return Promise.resolve(null);
  const w = window as unknown as { google?: { maps?: GoogleMaps }; __dineqrMaps?: () => void };
  if (w.google?.maps) return Promise.resolve(w.google.maps);
  mapsLoading ??= new Promise((resolve) => {
    w.__dineqrMaps = () => resolve(w.google?.maps ?? null);
    const script = document.createElement('script');
    script.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(googleMapsKey)}&callback=__dineqrMaps&v=weekly`;
    script.async = true;
    script.onerror = () => resolve(null);
    document.head.append(script);
  });
  return mapsLoading;
}

/** A map to drop the restaurant's pin on, with the radius drawn around it. */
function AreaMap({ lat, lng, radius, onPick }: { lat: number | null; lng: number | null; radius: number; onPick: (lat: number, lng: number) => void }) {
  const box = useRef<HTMLDivElement>(null);
  const objects = useRef<{ map: InstanceType<GoogleMaps['Map']>; marker: InstanceType<GoogleMaps['Marker']>; circle: InstanceType<GoogleMaps['Circle']> } | null>(null);
  const [failed, setFailed] = useState(false);
  const pick = useRef(onPick);
  pick.current = onPick;

  useEffect(() => {
    let alive = true;
    void loadGoogleMaps().then((maps) => {
      if (!alive || !box.current) return;
      if (!maps) return setFailed(true);
      const center = Geofence.isValidPoint(lat, lng) ? { lat: lat!, lng: lng! } : { lat: 20.5937, lng: 78.9629 };
      const map = new maps.Map(box.current, { center, zoom: Geofence.isValidPoint(lat, lng) ? 18 : 4, streetViewControl: false, mapTypeControl: false, fullscreenControl: false });
      const marker = new maps.Marker({ position: center, map, draggable: true, title: 'Restaurant' });
      const circle = new maps.Circle({ map, center, radius, strokeColor: '#d62828', strokeWeight: 2, fillColor: '#d62828', fillOpacity: 0.12, clickable: false });
      map.addListener('click', (e) => pick.current(e.latLng.lat(), e.latLng.lng()));
      marker.addListener('dragend', () => {
        const p = marker.getPosition();
        pick.current(p.lat(), p.lng());
      });
      objects.current = { map, marker, circle };
    });
    return () => {
      alive = false;
    };
    // The map is created once; position changes are applied below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const o = objects.current;
    if (!o || !Geofence.isValidPoint(lat, lng)) return;
    const p = { lat: lat!, lng: lng! };
    o.marker.setPosition(p);
    o.circle.setCenter(p);
    o.circle.setRadius(radius);
    o.map.panTo(p);
  }, [lat, lng, radius]);

  if (failed) return <p className="rounded-xl bg-panel-2 p-4 text-[12.5px] text-muted">Google Maps could not be loaded (check the API key and the connection). Enter the coordinates below instead.</p>;
  return <div ref={box} className="h-72 w-full overflow-hidden rounded-2xl border border-line bg-panel-2" aria-label="Map: click or drag the pin to the restaurant" />;
}

/**
 * Guests may order only within a radius of the restaurant, measured by the
 * server from the guest's GPS position (GpsRestrictionCard). Independent of
 * the Wi-Fi restriction; saved on its own.
 */
export function GpsRestrictionCard() {
  const query = useGeofence();
  const [enabled, setEnabled] = useState(false);
  const [takeaway, setTakeaway] = useState(false);
  const [radius, setRadius] = useState(50);
  const [custom, setCustom] = useState(false);
  const [customRadius, setCustomRadius] = useState('');
  const [latitude, setLatitude] = useState('');
  const [longitude, setLongitude] = useState('');
  const [locating, setLocating] = useState(false);
  const { pending, run } = useAction();

  const adopt = (s: GeofenceSettings) => {
    setEnabled(s.enabled);
    setTakeaway(s.takeaway);
    setRadius(s.radius);
    const isCustom = !(Geofence.presets as readonly number[]).includes(s.radius);
    setCustom(isCustom);
    setCustomRadius(isCustom ? String(s.radius) : '');
    setLatitude(s.latitude?.toFixed(6) ?? '');
    setLongitude(s.longitude?.toFixed(6) ?? '');
  };
  useEffect(() => {
    if (query.data) adopt(query.data);
  }, [query.data]);

  const lat = latitude.trim() ? Number.parseFloat(latitude) : null;
  const lng = longitude.trim() ? Number.parseFloat(longitude) : null;
  const point = Geofence.isValidPoint(lat, lng);
  const effectiveRadius = custom ? Number.parseInt(customRadius.trim(), 10) || 0 : radius;

  const setPoint = (a: number, b: number) => {
    setLatitude(a.toFixed(6));
    setLongitude(b.toFixed(6));
  };

  const useThisDevice = () => {
    if (!navigator.geolocation) return toast('Turn on location on this device, or pick the restaurant on the map.', 'error');
    setLocating(true);
    navigator.geolocation.getCurrentPosition(
      (position) => {
        setLocating(false);
        setPoint(position.coords.latitude, position.coords.longitude);
        toast(`Location set (±${Math.round(position.coords.accuracy)} m). Check the pin before saving.`, 'success');
      },
      (error) => {
        setLocating(false);
        toast(
          error.code === error.PERMISSION_DENIED ? "Allow DineQR Admin to use this device's location, or enter the coordinates." : "This device's location could not be read.",
          'error',
        );
      },
      { enableHighAccuracy: true, timeout: 20_000, maximumAge: 0 },
    );
  };

  const save = async () => {
    const next = { enabled, latitude: Number.isFinite(lat) ? lat : null, longitude: Number.isFinite(lng) ? lng : null, radius: effectiveRadius, takeaway };
    if (enabled && !query.data?.enabled) {
      const ok = await confirmDialog({
        title: 'Switch the GPS restriction on?',
        message: `Guests will have to allow location and be within ${effectiveRadius} m of the pin to place an order. Check the pin is on the restaurant: phones are often 10–30 m off indoors, so a very small radius may refuse guests at the far tables.`,
        confirmLabel: 'Switch on',
        icon: LocateFixed,
      });
      if (!ok) return;
    }
    await run(() => saveGeofence(next), { success: 'GPS configuration saved' });
  };

  const saved = query.data;
  return (
    <SectionCard
      title="GPS Location & Ordering Restrictions"
      subtitle="Guests can place orders only within a set distance of the restaurant, measured by the server from the guest's GPS position. Works alongside the Wi-Fi restriction: with both on, an order must pass both."
    >
      {!saved ? (
        <LoadState loading={query.isPending} error={query.error} onRetry={() => void query.refetch()} fallback="The GPS restriction could not be loaded." />
      ) : (
        <div className="flex flex-col gap-4">
          <InfoRow label="Restaurant" value={saved.restaurantName || '—'} />
          <p className="-mt-3 text-[12px] text-faint">The name is changed under Restaurant details above.</p>
          <div className="divide-y divide-line">
            <SwitchRow title="Enable GPS restriction" description="Off: guests order from anywhere, as before." checked={enabled} onChange={setEnabled} />
            <SwitchRow title="Include takeaway orders" description="Off: takeaway guests can order from anywhere." checked={takeaway} onChange={setTakeaway} />
          </div>
          <div>
            <p className="text-[14px] font-semibold text-ink">Restaurant location</p>
            <p className="text-[12.5px] text-muted">
              {googleMapsKey
                ? 'Click the map (or drag the pin) to drop it on the restaurant; the coordinates fill in by themselves.'
                : "Enter the coordinates, or use this device's location while at the restaurant. (A map appears when the app is built with a Google Maps API key.)"}
            </p>
          </div>
          {googleMapsKey && <AreaMap lat={lat} lng={lng} radius={effectiveRadius >= 10 ? effectiveRadius : 10} onPick={setPoint} />}
          <div className="grid grid-cols-2 gap-3">
            <TextField label="Latitude" placeholder="e.g. 13.082700" inputMode="decimal" value={latitude} onChange={(e) => setLatitude(e.target.value.replace(/[^-0-9.]/g, ''))} />
            <TextField label="Longitude" placeholder="e.g. 80.270700" inputMode="decimal" value={longitude} onChange={(e) => setLongitude(e.target.value.replace(/[^-0-9.]/g, ''))} />
          </div>
          <div className="flex flex-wrap gap-2">
            <Button size="sm" icon={LocateFixed} loading={locating} onClick={useThisDevice}>
              Use this device's location
            </Button>
            {point && (
              <Button size="sm" variant="ghost" icon={MapIcon} onClick={() => window.open(`https://www.google.com/maps/search/?api=1&query=${lat},${lng}`, '_blank', 'noopener,noreferrer')}>
                Open in Google Maps
              </Button>
            )}
          </div>
          <div>
            <p className="mb-2 text-[14px] font-semibold text-ink">Ordering radius</p>
            <div className="flex flex-wrap gap-2" role="radiogroup" aria-label="Ordering radius">
              {Geofence.presets.map((preset) => (
                <button key={preset} type="button" role="radio" aria-checked={!custom && radius === preset} onClick={() => (setCustom(false), setRadius(preset))} className={cn('h-9 rounded-full border px-4 text-[13px] font-semibold', !custom && radius === preset ? 'border-transparent brand-fill' : 'border-line bg-panel-2 text-muted hover:text-ink')}>
                  {preset} m
                </button>
              ))}
              <button type="button" role="radio" aria-checked={custom} onClick={() => (setCustom(true), setCustomRadius(customRadius || String(radius)))} className={cn('h-9 rounded-full border px-4 text-[13px] font-semibold', custom ? 'border-transparent brand-fill' : 'border-line bg-panel-2 text-muted hover:text-ink')}>
                Custom
              </button>
            </div>
            {custom && (
              <div className="mt-3 max-w-xs">
                <TextField label="Radius in metres (10 to 1000)" inputMode="numeric" suffix="m" value={customRadius} onChange={(e) => setCustomRadius(e.target.value.replace(/\D/g, ''))} />
              </div>
            )}
            <p className="mt-2 text-[12px] leading-relaxed text-faint">
              Phones are usually accurate to 5–20 m outdoors and less indoors, so 30–50 m suits most restaurants. The server allows for part of that uncertainty, refuses readings that are too vague, out of date or from a mock-location app, and never stores positions.
            </p>
          </div>
          {saved.updatedAt && (
            <p className="text-[12px] text-faint">
              Last saved {AppFormat.dateTime(saved.updatedAt)}
              {saved.updatedBy ? ` by ${saved.updatedBy}` : ''}
              {saved.createdAt ? ` · set up ${AppFormat.date(saved.createdAt)}` : ''}
            </p>
          )}
          <Button variant="primary" icon={Check} loading={pending} onClick={() => void save()} className="self-start">
            Save GPS configuration
          </Button>
        </div>
      )}
    </SectionCard>
  );
}
