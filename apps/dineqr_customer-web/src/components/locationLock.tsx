import { LocateFixed, LocateOff, MapPinOff, Radar, RefreshCw } from 'lucide-react';
import type { ReactNode } from 'react';
import { useNavigate } from 'react-router';
import { paths } from '../routes/paths';
import { useApp } from '../state/app';
import { useStore } from '../state/store';
import { iconSize } from './sizes';
import { Button, IconHalo } from './ui';

/**
 * Shows the ordering screens only while the GPS ordering area is satisfied
 * (or does not apply). The server refuses orders from outside anyway; this
 * says why and opens again once a check passes. Separate from the
 * restaurant Wi-Fi check.
 */
export function LocationGate({ children }: { children: ReactNode }) {
  const { location } = useApp();
  useStore(location);
  if (!location.isLocked) return <>{children}</>;
  return <LocationLockPanel />;
}

export function LocationLockPanel() {
  const { location } = useApp();
  useStore(location);
  const navigate = useNavigate();
  const state = location.state;
  const title =
    state === 'checking'
      ? 'Checking your location'
      : state === 'outside'
        ? 'You are too far from the restaurant'
        : state === 'permissionDenied'
          ? 'Allow location to order'
          : state === 'serviceDisabled'
            ? 'Turn on location'
            : 'Location needed to order';
  const icon =
    state === 'outside' ? <MapPinOff size={iconSize.hero} /> : state === 'checking' ? <LocateFixed size={iconSize.hero} /> : <LocateOff size={iconSize.hero} />;
  return (
    <div className="entry entry--center location-lock" role="alert">
      <IconHalo>{icon}</IconHalo>
      <h1 className="t-headline t-center">{title}</h1>
      <p className="t-center location-lock__message">{location.explanation}</p>
      {location.radius > 0 && (
        <p className="location-lock__radius t-label">
          <Radar size={iconSize.md} /> Ordering within {location.radius} m of the restaurant
        </p>
      )}
      <Button block icon={<RefreshCw size={iconSize.md} />} loading={location.checking} onClick={() => void location.verify()} data-testid="location-retry">
        {state === 'permissionDenied' ? 'Allow location' : 'Try again'}
      </Button>
      <Button variant="ghost" muted block onClick={() => navigate(paths.scan)}>
        Scan a different code
      </Button>
    </div>
  );
}
