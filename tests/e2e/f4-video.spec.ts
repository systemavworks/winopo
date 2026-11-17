import { expect, test } from '@playwright/test'

test.describe('F4 · vídeo', () => {
  test.fixme('el vídeo de un tema se marca desactualizado al cambiar de versión', async ({ page }) => {
    await page.goto('/opositor')
    await expect(page.getByRole('heading', { name: 'Mi preparación' })).toBeVisible()
  })
})
