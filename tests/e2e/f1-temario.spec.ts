import { expect, test } from '@playwright/test'

test.describe('F1 · temario y opositores', () => {
  test.fixme('el preparador da de alta un opositor y este puede entrar', async ({ page }) => {
    await page.goto('/preparador')
    await expect(page.getByRole('heading', { name: 'Panel del preparador' })).toBeVisible()
  })

  test.fixme('publicar tema v1, editar a v2 y el opositor ve v2 con histórico', async ({ page }) => {
    await page.goto('/preparador')
  })
})
