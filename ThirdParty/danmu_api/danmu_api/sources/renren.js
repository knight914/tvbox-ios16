// Disabled in iOS distribution: no signed cross-client fallback or embedded credentials.
import BaseSource from './base.js';
export class RenrenSource extends BaseSource { async search() { return []; } async getDetail() { return []; } }
