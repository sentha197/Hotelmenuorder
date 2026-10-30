import { MotionConfig } from 'motion/react';
import { useState } from 'react';
import { createBrowserRouter, RouterProvider, type DataRouter } from 'react-router';
import { apiConfig, apiConfigIssue, basePath } from './config';
import { NotConfiguredPage } from './pages/MiscPages';
import { routes } from './routes/routes';
import { AppContext, createApp, type AppServices } from './state/app';

/** The app with its services and router; tests pass their own of each. */
export function AppRoot({ app, router }: { app: AppServices; router: DataRouter }) {
  return (
    <AppContext value={app}>
      {/* "user": animations follow the device's reduced-motion setting. */}
      <MotionConfig reducedMotion="user">
        <RouterProvider router={router} />
      </MotionConfig>
    </AppContext>
  );
}

export function App() {
  const [app] = useState(() => (apiConfig ? createApp(apiConfig) : null));
  const [router] = useState(() => createBrowserRouter(routes, { basename: basePath.replace(/\/$/, '') || '/' }));
  if (!app) return <NotConfiguredPage issue={apiConfigIssue!} />;
  return <AppRoot app={app} router={router} />;
}
