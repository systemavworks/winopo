import { expect, test } from '@playwright/test'

test.describe('F3 · supuestos', () => {
  test.fixme('entrega, corrección IA, validación del preparador y nota final', async ({ page }) => {
    await page.goto('/opositor')
    await expect(page.getByRole('heading', { name: 'Mi preparación' })).toBeVisible()
  })
})
