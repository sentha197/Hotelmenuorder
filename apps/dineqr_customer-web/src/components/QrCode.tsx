import QRCode from 'qrcode';
import { useMemo } from 'react';

/**
 * A QR code drawn as SVG paths (sharp at any size, printable). [payload] is
 * encoded as given: it is shown, never followed.
 */
export function QrCode({ payload, size = 220, label, branded = false }: { payload: string; size?: number; label: string; branded?: boolean }) {
  const path = useMemo(() => {
    const qr = QRCode.create(payload, { errorCorrectionLevel: branded ? 'H' : 'M' });
    const count = qr.modules.size;
    const data = qr.modules.data;
    let d = '';
    for (let y = 0; y < count; y++) {
      for (let x = 0; x < count; x++) {
        if (data[y * count + x]) d += `M${x} ${y}h1v1h-1z`;
      }
    }
    return { d, count };
  }, [payload, branded]);
  const quiet = 2;
  const view = path.count + quiet * 2;
  return (
    <svg
      width={size}
      height={size}
      viewBox={`${-quiet} ${-quiet} ${view} ${view}`}
      role="img"
      aria-label={label}
      shapeRendering="crispEdges"
      style={{ display: 'block', maxWidth: '100%', height: 'auto', background: '#fff', borderRadius: 8 }}
    >
      <path d={path.d} fill={branded ? '#3A0508' : '#000'} />
    </svg>
  );
}
