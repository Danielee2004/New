# 🌟 StarNote – On-Chain Micro-Poems & Likes ✨

> "Every line is a star. Every like is a constellation." 🌌  

StarNote is a **unique Clarity smart contract** on Stacks that transforms the blockchain into a **living constellation of thoughts, poems, and micro-notes**.  
It’s not about money, lotteries, or vaults — it’s about **human expression, permanence, and community recognition.**

---

## 💡 The Idea

In the noise of social media, posts disappear, feeds refresh, and memories fade.  
But what if **your words could live forever, secured by the blockchain**?  

StarNote makes that possible.  
- Users can post **short notes or micro-poems** (140 characters, like the early days of Twitter).  
- Anyone can **like a post** — one like per person, ensuring fairness.  
- The contract automatically tracks the **leading post** (the one with the most likes).  

This creates a **permanent, verifiable record** of creativity and community love.  
Your note isn’t just text anymore — it’s **immortalized as part of the Stacks chain**. 🌌

---

## ✨ Features

- 📝 **Post Micro-Notes / Poems**  
  Share short ASCII notes (up to 140 characters). Your words become permanent, stored immutably.  

- 👍 **Like Posts (One Per Person)**  
  Every wallet address can like a post once, making support **fair and authentic**.  

- 🏆 **Leading Post Tracker**  
  The contract always remembers the current **#1 post**, determined by total likes.  
  In the event of a tie, the **earlier post wins** (first star to shine).  

- 🌐 **Publicly Verifiable**  
  Anyone can read posts, likes, and rankings using only blockchain calls.  

---

## 🚀 How It Works

### 1. Post a StarNote
```clarity
(contract-call? .starnote post "Dawn breaks, code sings")
