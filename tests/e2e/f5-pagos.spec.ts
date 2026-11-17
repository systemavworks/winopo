import { expect, test } from '@playwright/test'

test.describe('F5 · pagos', () => {
  test.fixme('compra de prueba, webhook, acceso concedido y consentimiento guardado', async ({ page }) => {
    await page.goto('/preparador')
    await expect(page.getByRole('heading', { name: 'Panel del preparador' })).toBeVisible()
  })
})
