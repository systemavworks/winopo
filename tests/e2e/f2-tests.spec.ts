import { expect, test } from '@playwright/test'

test.describe('F2 · tests', () => {
  test.fixme('test de 30 preguntas: nota en céntimos y desglose por tema', async ({ page }) => {
    await page.goto('/opositor')
    await expect(page.getByRole('heading', { name: 'Mi preparación' })).toBeVisible()
  })
})
