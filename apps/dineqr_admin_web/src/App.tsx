import { QueryClientProvider } from '@tanstack/react-query';
import { MotionConfig } from 'motion/react';
import { useState } from 'react';
import { createBrowserRouter, RouterProvider } from 'react-router';
import { apiConfigIssue, basePath } from './config/env';
import { NotConfiguredScreen } from './pages/auth/AuthPages';
import { routes } from './routes/router';
import { backend } from './services/backend';
import { queryClient } from './state/data';
import { Session } from './state/session';

let started = false;

/** Restores the saved session once, while waking an idle server. */
function start() {
  if (started || !backend) return;
  started = true;
  backend.auth.onSessionLost = (message) => Session.lost(message);
  void backend.api.warmUp();
  void Session.restore();
}

export function App() {
  const [router] = useState(() => createBrowserRouter(routes, { basename: basePath.replace(/\/$/, '') || '/' }));
  if (!backend) return <NotConfiguredScreen issue={apiConfigIssue} />;
  start();
  return (
    <QueryClientProvider client={queryClient}>
      {/* "user": animations follow the device's reduced-motion setting (fades stay). */}
      <MotionConfig reducedMotion="user">
        <RouterProvider router={router} />
      </MotionConfig>
    </QueryClientProvider>
  );
}
